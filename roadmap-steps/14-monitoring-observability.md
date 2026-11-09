# Step 14: Monitoring and observability

**Inputs:** Step 0 (NFR-05, QAS-13: alert within 5 min with a trace that shows the failing dependency, latency QAS-06/07/08, availability QAS-01), Step 2 (incident reports to the SB within 5 days and root cause within 10; synchronized clocks), Step 8 (Kong, Kafka, Istio), Step 10 (audit is separate from logs), Step 12 (SIEM via Security Lake), Step 13 (SLOs per tier, synthetic checks for failover).

---

## 1. Signals and how they connect

| Signal | What | Standard / tool |
| --- | --- | --- |
| **Traces** | One request across app → CloudFront → Kong → BFF → services → Kafka → consumers → Core Adapter | **OpenTelemetry**, W3C Trace Context (`traceparent`) |
| **Metrics** | Technical (latency, errors, saturation) and **business** (transfers per minute, rejection rate, onboarding funnel) | OpenTelemetry metrics → Prometheus |
| **Logs** | Structured JSON, one line per event, with `traceId` / `spanId` | OpenTelemetry logs / Fluent Bit |
| **Real-user monitoring** | Screen load time, errors, crashes on web and mobile | CloudWatch RUM (web), Firebase Crashlytics + OTel spans (Flutter) |
| **Synthetic checks** | Scripted login, balance, own transfer from outside AWS (ideally from Ecuador) | CloudWatch Synthetics + an external probe with Latin American locations |

**Correlation ID = trace ID.** It's created at the edge (or by the app), propagated in HTTP headers **and Kafka message headers**, written in every log line and audit record (Step 10), and returned to the app in a response header so customer support can find a customer's failed request in seconds. That covers QAS-13: one trace shows which dependency failed.

**Clocks:** Amazon Time Sync on every host (Step 2), so timestamps across services, logs and audit match.

---

## 2. Service level objectives (SLOs)

Measured at the gateway and by synthetic checks, monthly window.

| Journey | SLI | SLO | Error budget per month |
| --- | --- | --- | --- |
| Login | Successful logins / attempts (excluding wrong password) | 99.95% | ~22 min |
| Dashboard (frequent client) | Requests answered < 500 ms and without error | 99.9% fast, **99.99% available** | ~4.3 min unavailable |
| Movement history (3 months) | p95 latency | < 1.5 s | — |
| Own-account transfer | Confirmed < 3 s and without system error | 99.9% fast, 99.99% available | ~4.3 min |
| Interbank transfer | "Accepted" < 3 s; final status within network time | 99.99% / 99.9% | ~4.3 min |
| **Incoming interbank payment** | Answered (`pacs.002`) within the network timeout | **99.99%** | ~4.3 min |
| Regulatory notification | SMS and email handed to provider < 60 s (QAS-04) | 99.9% | |
| Onboarding | Cases without system error | 99.5% | |

**Error budget policy:** if a journey burns its monthly budget, feature releases to the services in that journey stop until reliability work brings it back. That gives a measurable balance between change speed and stability, which the 2025 outages showed was missing.

---

## 3. Alerting and on-call

| Rule | How |
| --- | --- |
| Alert on **symptoms** (SLO burn), not on every CPU spike | **Multi-window burn-rate alerts**: page if 2% of the monthly budget burns in 1 h (fast burn, checked over 1 h and 5 min windows) or 5% in 6 h (slow burn) |
| Meets QAS-13 (≤ 5 min) | Fast-burn alert evaluates every minute; synthetic journeys every minute from outside |
| Causes go to dashboards, not pagers | Saturation, queue lag, circuit-breaker state, Core latency |
| Every page has a runbook link | Runbooks in Git, linked from the alert |
| On-call tool | **PagerDuty** (or the bank's current tool). **Avoid Opsgenie** (end of sale Jun 2025, **end of support 5 Apr 2027**) and AWS Systems Manager **Incident Manager** (closed to new customers since 7 Nov 2025) |
| Incident process | Severity levels, incident commander, status page for customers, post-incident review (blameless) feeding the **SB reports** (5 days formal, 10 days root cause) |

---

## 4. Business and dependency monitoring

| Dashboard | Signals |
| --- | --- |
| **Transfers** | Transfers per minute vs same minute last week (anomaly detection), success / rejection by reason, step-up rate, p95 confirmation time, interbank `PENDING` / `UNKNOWN` count and age |
| **Incoming payments** | Received per minute, answer time vs network timeout, rejections |
| **Core health** (seen from our side) | Core Adapter latency and errors, circuit state, rate-limiter rejections, read-model freshness (CDC lag) |
| **Customer experience** | App crash-free sessions, screen load times, login failures (also an attack indicator), "as of" fallback rate |
| **Notifications** | Delivery rate and time per provider, failovers, DLQ size, SMS cost per day |
| **Onboarding funnel** | Started → document → liveness → registry → approved, drop-off per step, manual review queue age |
| **Caching** | Hit ratio of dashboards and balances, pre-warm progress before payday |
| **DR readiness** | Aurora global lag, MSK Replicator lag, DynamoDB replication latency, standby capacity |
| **Cost** | Daily spend per service and per environment (Step 15) |

---

## 5. ADR-019: Observability platform

**Status:** Proposed

| Criterion | Weight | AWS-managed open-source stack | Datadog | Dynatrace | Self-hosted Grafana stack (LGTM) |
| --- | --- | --- | --- | --- | --- |
| Open standards / portability (OTel, PromQL) | 20% | 5 | 4 | 4 | 5 |
| Telemetry stays in the bank's AWS account (personal data in logs) | 20% | 5 | 2 | 2 | 5 |
| Cost at this volume | 20% | 4 | 2 | 2 | 4 |
| Features (APM, correlation, RUM, anomaly detection) | 15% | 3 | 5 | 5 | 4 |
| Operational effort | 15% | 4 | 5 | 5 | 2 |
| Ecosystem and team familiarity | 10% | 4 | 5 | 4 | 4 |
| **Weighted total** | 100% | **4.25** | **3.60** | **3.50** | **4.10** |

**Decision:** **OpenTelemetry everywhere**, collected with the **AWS Distro for OpenTelemetry (ADOT)** and sent to:

- **Metrics:** Amazon Managed Service for Prometheus.
- **Traces:** AWS X-Ray / CloudWatch Application Signals through the **OTLP** endpoint (no X-Ray SDKs: they entered maintenance mode on 25 Feb 2026 and reach **end of support on 25 Feb 2027**).
- **Logs:** CloudWatch Logs (Infrequent Access class for high-volume logs), 30 days online, then exported to S3.
- **Dashboards and alerts:** Amazon Managed Grafana (one place for metrics, traces and logs).
- **Security events:** Security Lake → bank SIEM (Step 12).

### Justifications

1. **Vendor-neutral instrumentation.** Services are instrumented once with OpenTelemetry; the back end can change (e.g. to Datadog or Grafana Cloud) by changing the collector's exporter, not the code. It's also AWS's recommended path now that the X-Ray SDKs are being retired.
2. **Telemetry stays in the bank's AWS account.** Logs and traces can contain personal data despite redaction. Keeping them in the account avoids another international processor under the LOPDP and simplifies the SB dossier.
3. **Cost that follows usage.** Managed Prometheus and Grafana are priced by samples and users, not per host or per GB as with most SaaS APM tools, which matters with hundreds of pods and payday scale-outs.

**Trade-off:** less "out of the box" intelligence than Datadog or Dynatrace (automatic root-cause analysis). If the bank already licenses one of them, OpenTelemetry makes switching cheap.

---

## 6. Component design

```text
 Flutter app ──(OTel spans, Crashlytics)──┐        Web SPA ──(CloudWatch RUM)──┐
                                          ▼                                    ▼
 CloudFront logs ─► S3          Kong (OTel plugin) ─► BFFs ─► services (OTel Java agent, auto + manual spans)
                                          │                │ Kafka headers carry traceparent
                                          ▼                ▼
                     ADOT Collector (DaemonSet + gateway deployment, per region)
                       ├─ processors: PII redaction, tail sampling, resource attributes
                       ├─► Amazon Managed Prometheus (metrics, SLO recording rules)
                       ├─► X-Ray / Application Signals (traces, OTLP)
                       └─► CloudWatch Logs ─► S3 archive
                                          │
                     Amazon Managed Grafana: SLO, business, dependency, DR dashboards
                       └─► Alert rules (burn rate) ─► PagerDuty ─► on-call
 CloudWatch Synthetics + external probes (Ecuador) ─► same alerting
 GuardDuty / Security Hub / CloudTrail ─► Security Lake ─► bank SIEM / SOC (Step 12)
```

| Pattern | Where |
| --- | --- |
| **Distributed tracing** with context propagation | HTTP + Kafka headers |
| **Health check API** | Liveness / readiness endpoints (Step 13) |
| **Log aggregation** | Collector → CloudWatch Logs |
| **Application metrics** + **SLO recording rules** | Prometheus |
| **Sidecar-less collection** | DaemonSet collectors + Istio ambient telemetry |

---

## 7. Rules for telemetry content

| Rule | Detail |
| --- | --- |
| No personal data in logs or spans | No names, cédula, phone, email, full account numbers, tokens, OTPs. Use customer ID / tokenized IDs. **Redaction processor** in the collector as a safety net. |
| Structured logs | JSON with `timestamp`, `level`, `service`, `version`, `traceId`, `spanId`, `event`, `outcome` |
| Sampling | **Tail sampling**: keep 100% of error and slow traces, ~5–10% of successful ones; metrics are never sampled |
| Cardinality | No customer IDs as metric labels (put them in traces/logs instead) |
| Retention | Metrics 15 months (year-over-year comparison for payday), traces 30 days, logs 30 days online + 1 year archive. Audit is separate (Step 10). |
| Multi-region | Each region has its own collectors and workspaces; Grafana shows both; dashboards survive a regional failover |

---

## 8. Sizing and cost hints (detailed in Step 15)

- Logs are usually the biggest observability cost. Levers: Infrequent Access log class, no debug logs in production by default (enabled per service on demand), and S3 export.
- Traces: tail sampling keeps volume around 10% of requests.
- Metrics: avoid high-cardinality labels.

---

## 9. Sources

- [OpenTelemetry documentation](https://opentelemetry.io/docs/)
- [AWS: X-Ray SDKs / Daemon end of support timeline](https://docs.aws.amazon.com/xray/latest/devguide/xray-daemon-eos.html)
- [AWS blog: X-Ray SDK end of support and OpenTelemetry migration](https://aws.amazon.com/blogs/mt/announcing-aws-x-ray-sdks-daemon-end-of-support-and-opentelemetry-migration)
- [AWS Distro for OpenTelemetry](https://aws-otel.github.io/)
- [Amazon Managed Service for Prometheus](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) and [Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/latest/userguide/what-is-Amazon-Managed-Service-Grafana.html)
- [Google SRE Workbook: alerting on SLOs (burn rate)](https://sre.google/workbook/alerting-on-slos/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [AWS: Incident Manager availability change](https://docs.aws.amazon.com/incident-manager/latest/userguide/incident-manager-availability-change.html)
- [Atlassian: Opsgenie migration (end of support)](https://www.atlassian.com/software/opsgenie/migration)

---

## Step 14 checklist

- [x] Signals, OpenTelemetry and correlation ID across HTTP and Kafka
- [x] SLOs and error budgets per journey
- [x] Alerting (burn rate, ≤ 5 min) and on-call, avoiding retiring tools
- [x] Business and dependency dashboards
- [x] Platform chosen (ADR-019), including the X-Ray SDK retirement
- [x] Component design and telemetry content rules (PII, sampling, retention)
- [x] Add the observability stack to the deployment view (Step 17): one node per region
