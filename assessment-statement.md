# Solution Architect BP: Ejercicio práctico

> Fuente: `IDE CoderPad Screen.html` (Question 1 / 1, Solution Architect BP). Tiempo de resolución: **72 horas**.

---

## 1. Entregables

1. **Documento PDF** con la respuesta al ejercicio.
   - Bien organizado y fácil de leer.
   - Incluir imágenes para explicar los diagramas (por ejemplo, con [draw.io](http://draw.io/)).
   - Añadir todo el texto explicativo que se considere necesario.
2. **Subir el PDF** como respuesta al ejercicio en CoderPad, **antes de que termine el tiempo**.
3. **Repositorio público en GitHub** con el PDF. Poner la URL del repositorio en el comentario al reclutador.

> **Importante:** cada diagrama C4 es un entregable clave. Deben ser correctos y detallados. También hay que cuidar los demás diagramas requeridos.

### Recomendación muy valorada

- **Cada decisión arquitectónica debe tener una justificación teórica, con un mínimo de 2 por decisión.** Por ejemplo: ¿por qué se eligieron ciertos patrones, tecnologías, componentes o protocolos? ¿Qué otras opciones se evaluaron?

---

## 2. Diagramas requeridos (modelo C4, hasta el nivel de componentes)

| Diagrama | Audiencia | Contenido esperado |
|---|---|---|
| **Contexto** | Usuarios no técnicos | Sistemas internos y externos, actores clave, descripciones breves y conexiones explicadas. |
| **Contenedores** | Técnicos | Aplicaciones, servicios, bases de datos y mensajería, incluidos los componentes cloud sin mucho detalle. Conexiones con descripciones breves. |
| **Componentes** | Mayor detalle técnico | Microservicios, patrones arquitectónicos, protocolos de comunicación y su seguridad. Debe destacar el uso de componentes cloud. |
| **Infraestructura** | Libre | Se puede modelar como se prefiera, con la herramienta que se elija. |

---

## 3. Descripción del ejercicio

BP contrata a un **arquitecto de soluciones** para diseñar un **sistema de banca por internet**. En él, los usuarios podrán:

- Consultar el **histórico de movimientos**.
- Hacer **transferencias y pagos** entre cuentas propias e **interbancarias**.

### 3.1 Fuentes de datos del cliente

- **Plataforma Core:** datos básicos del cliente, movimientos y productos.
- **Sistema independiente complementario:** amplía la información del cliente cuando se requieren datos en detalle.

### 3.2 Notificaciones

- La normativa exige notificar a los usuarios sobre los movimientos realizados.
- Se deben usar **al menos 2** sistemas de envío de notificaciones, externos o propios.

### 3.3 Front-end

- **SPA** (aplicación web).
- **Aplicación móvil** con un **framework multiplataforma**: hay que **mencionar 2 opciones y justificar la elegida**.

### 3.4 Autenticación (OAuth 2.0)

- Ambas aplicaciones autentican a los usuarios con un servicio basado en **OAuth 2.0**.
- No hace falta implementar la lógica, porque la compañía ya tiene un producto configurable para esto.
- **Se debe recomendar el mejor flujo de autenticación según el estándar.**

### 3.5 Onboarding con reconocimiento facial

- El onboarding de nuevos clientes en la app móvil usa **reconocimiento facial**. La arquitectura debe incluirlo en el flujo de autorización y autenticación.
- Después del onboarding, el usuario podrá entrar con **usuario y clave, huella u otro método**. Hay que especificar en la arquitectura cuál o cuáles se usan.
- Se pueden recomendar **herramientas de la industria** que hagan estas tareas y robustezcan la aplicación.

### 3.6 Auditoría y clientes frecuentes

- Hay una **base de datos de auditoría** que registra todas las acciones del cliente.
- Hay un **mecanismo de persistencia de información para clientes frecuentes**.
- **Se debe proponer una alternativa basada en patrones de diseño** que relacione los componentes que deben interactuar para lograrlo.

### 3.7 Capa de integración

- Los datos del cliente se obtienen a través de una **capa de integración con un API Gateway**, que consume los servicios necesarios según el tipo de transacción.
- Servicios iniciales:
  1. Consulta de datos básicos.
  2. Consulta de movimientos.
  3. Transferencias, que llaman a servicios externos según el tipo.
- Se pueden **añadir más servicios** para mejorar el rendimiento o la respuesta a los clientes.

---

## 4. Consideraciones

- **Normativa:** mencionar los elementos regulatorios relevantes para entidades financieras (por ejemplo, ley de protección de datos personales, seguridad, etc.).
- **Atributos de calidad que la arquitectura debe garantizar:**
  - Alta disponibilidad (HA)
  - Tolerancia a fallos
  - Recuperación ante desastres (DR)
  - Seguridad y monitoreo
  - Excelencia operativa
  - Auto-healing
- **Nube:** se puede usar infraestructura en **Azure o AWS**. Hay que garantizar **baja latencia**. Se cuenta con presupuesto para ello.
- **Desacoplamiento:** en lo posible, una arquitectura desacoplada, con elementos reutilizables y cohesionados para componentes futuros.
- **Modelo C4:** contexto, contenedores y componentes. La infraestructura se modela libremente.

---

## 5. Criterios de calificación

1. Que la solución cumpla los requerimientos y todo esté justificado.
2. Calidad y profundidad de los diagramas (contexto, contenedores y componentes).
3. Segmentación de responsabilidades y desacoplamiento.
4. Uso de patrones de arquitectura.
5. Integración con servicios externos.
6. Calidad de la arquitectura front-end y móvil.
7. Arquitectura de acceso a datos.
8. Conocimientos de nube (AWS o Azure).
9. Manejo de costos.
10. Arquitectura de autenticación.
11. Arquitectura de integración con el onboarding.
12. Diseño de la solución de auditoría.
13. Conocimiento de regulaciones bancarias y estándares de seguridad.
14. Implementación de alta disponibilidad y tolerancia a fallos.
15. Implementación de monitoreo.

---

## 6. Checklist de cobertura

- [ ] Diagrama de contexto C4
- [ ] Diagrama de contenedores C4
- [ ] Diagrama de componentes C4
- [ ] Diagrama de infraestructura (cloud: AWS o Azure)
- [ ] 2 opciones de framework móvil multiplataforma, con la elección justificada
- [ ] Flujo OAuth 2.0 recomendado, con justificación
- [ ] Onboarding con reconocimiento facial integrado en authN/authZ, con herramientas sugeridas
- [ ] Métodos de login posteriores al onboarding (clave, biometría, etc.)
- [ ] Al menos 2 canales o proveedores de notificación
- [ ] Integración con el Core y con el sistema complementario de datos del cliente
- [ ] API Gateway más servicios (datos básicos, movimientos, transferencias y otros adicionales)
- [ ] Solución de auditoría y persistencia para clientes frecuentes basada en patrones de diseño
- [ ] Normativa y regulaciones aplicables
- [ ] HA, tolerancia a fallos, DR, seguridad, monitoreo, excelencia operativa y auto-healing
- [ ] Baja latencia y manejo de costos
- [ ] Al menos 2 justificaciones teóricas por decisión, con las alternativas evaluadas
- [ ] PDF subido a CoderPad y a un repositorio público de GitHub, con la URL en el comentario
