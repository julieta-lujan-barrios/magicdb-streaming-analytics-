# MagicDB — Modelo de datos y dashboard analítico para una plataforma SaaS de streaming

Diseño e implementación completa de una base de datos analítica en SQL Server para **Magic**, una plataforma SaaS orientada a streamers y creadores de contenido, junto con su capa de acceso (vistas y stored procedures) y un dashboard en Grafana que responde preguntas de negocio concretas sobre monetización, actividad y retención de usuarios.

Proyecto desarrollado para la materia **Bases de Datos** — Ingeniería en Inteligencia Artificial, 3er año — Universidad del Norte Santo Tomás de Aquino (UNSTA). Defendido oralmente y aprobado sin correcciones.

<img width="1636" height="922" alt="Captura de pantalla 2026-08-15 a la(s) 12 31 09" src="https://github.com/user-attachments/assets/37cc0447-1a00-4d0f-b048-439b1b52f8b6" />


---

## 📋 Tabla de contenidos

- [El problema](#el-problema)
- [Stack técnico](#stack-técnico)
- [Modelo de datos](#modelo-de-datos)
- [Decisiones de diseño destacadas](#decisiones-de-diseño-destacadas)
- [Capa de acceso](#capa-de-acceso)
- [Dashboard](#dashboard)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Cómo correrlo](#cómo-correrlo)
- [Datos sintéticos](#datos-sintéticos)
- [Autores](#autores)
- [Licencia](#licencia)

---

## El problema

Magic ofrece herramientas para que streamers configuren canales de transmisión, administren alertas interactivas en vivo, activen juegos para su audiencia y compren recursos digitales (assets) para personalizar sus transmisiones. La plataforma monetiza mediante un modelo de **suscripción por planes** (free, agency, pro, premium) y una **tienda de assets digitales**.

El objetivo del proyecto fue construir la base de datos que sostiene el análisis comercial y operativo de la plataforma, capaz de responder preguntas como:

- ¿Qué tipos de assets prefieren comprar los streamers y cuál es el producto más vendido?
- ¿Qué porcentaje de usuarios registrados convierte en comprador activo de la tienda?
- ¿Cuántos usuarios hacen upgrade o downgrade de plan, y en qué dirección?
- ¿Qué días y horarios concentran los picos de actividad de alertas en vivo?
- ¿Cómo se distribuye la facturación de la tienda a lo largo del mes y del año?

La base es un recorte deliberado de una plataforma SaaS real: se excluyeron a propósito los módulos de autenticación, tokens de integración con Twitch/YouTube, facturación legal y datos técnicos, porque no aportan a las preguntas de negocio planteadas y porque no corresponde trabajar con información sensible en un entorno académico. Todos los datos cargados son **sintéticos**.

## Stack técnico

- **SQL Server** — motor de base de datos y lenguaje T-SQL para todo el modelo, la capa de acceso y la generación de datos.
- **Docker / OrbStack** — contenedor `sqlserver-magicdb` corriendo SQL Server, con una imagen versionada (`sqlserver-magicdb-backup`) para persistir el estado de la base.
- **Grafana** — dashboard conectado directamente a SQL Server (`host.docker.internal`), consumiendo únicamente vistas y stored procedures.

## Modelo de datos

- **12 tablas** normalizadas, agrupadas en catálogo/configuración (`Planes`, `CatalogoJuegos`, `AssetsTienda`), usuarios y suscripciones, proyectos y alertas, y tablas relacionales N:M (`JuegosUsuarios`, `ComprasAssets`).
- Modelo conceptual, lógico y físico documentados de punta a punta, con cardinalidades justificadas y supuestos explícitos para cada decisión de diseño.
- Política de `ON DELETE` definida caso por caso: `CASCADE` cuando el registro hijo no tiene sentido sin el padre (proyectos, suscripciones de un usuario), `NO ACTION` cuando el registro hijo tiene valor histórico independiente (compras de un asset descontinuado, eventos de un usuario dado de baja).

## Decisiones de diseño destacadas

Lo que distingue este proyecto de un TP genérico de modelado es que cada decisión está documentada y justificada, no solo implementada. Algunos ejemplos:

- **Normalización de catálogos referenciales.** `EstadosSuscripcion` y `TiposAlerta` se extrajeron a tablas propias en lugar de dejarlos como `VARCHAR` con `CHECK`, evitando anomalías de actualización (renombrar un estado sin tocar cada fila que lo usa), inserción (dar de alta un tipo nuevo sin necesitar una fila que lo "porte") y eliminación (no perder el catálogo de valores válidos al borrar el último registro que los usaba).
- **Especialización sin herencia física.** `AlertasEventos` concentra eventos de distintos tipos de alerta, con un único atributo diferencial (`ValorDonado`, propio de las alertas tipo *tip*). Se evaluaron tres estrategias de herencia clásicas y se optó por absorber la especialización en una sola tabla, evitando joins innecesarios en el 90% de las consultas analíticas.
- **Corrección de fan-out en joins 1:N.** Vistas que combinan usuarios con su historial de suscripciones usan CTE + funciones de ventana (`ROW_NUMBER`, `LAG`) para evitar que un JOIN directo multiplique filas cuando un usuario tiene más de una suscripción histórica.
- **Índices justificados por query, no por regla general.** Los 3 índices no agrupados se crearon únicamente donde se pudo identificar la consulta concreta que optimizan (con `INCLUDE` para volverlos cubrientes); si no se podía justificar el impacto en el plan de ejecución, el índice no se creó.
- **Vistas vs. stored procedures por criterio explícito.** Las vistas resuelven preguntas de negocio fijas sin parámetros; los stored procedures se reservaron para consultas que dependen de un parámetro elegido en el momento (rango de fechas, tipo de asset, usuario puntual) o que requieren validación de entrada con `RAISERROR`.

## Capa de acceso

Por consigna del trabajo, **el dashboard no puede consultar tablas directamente** — toda extracción de datos pasa por una vista o un stored procedure. Esto se verificó explícitamente en cada panel de Grafana.

- **8 vistas**, cada una con un propósito de negocio claro (mínimo pedido: 5).
- **3 stored procedures** parametrizados, con validación de entrada:
  - `sp_BuscarComprasAssets` — ventas filtradas por rango de fechas y tipo de asset opcional.
  - `sp_FichaRendimientoStreamer` — perfil consolidado de un streamer puntual (plan actual, proyectos, alertas, donaciones, compras).
  - `sp_ReporteDonacionesRango` — segmentación de donaciones por monto mínimo y máximo.
- Uso de **CTE**, **funciones de ventana** (`RANK`, `LAG`, `ROW_NUMBER`), **subconsultas correlacionadas** y una **función escalar** (`fn_SemanaMes`) para centralizar lógica de cálculo reutilizada en varias vistas.

## Dashboard

8 indicadores en Grafana, cada uno atado a una pregunta de negocio documentada (qué vista o SP lo alimenta, qué se ve, qué decisión tomaría la organización con esa información): popularidad de assets por categoría, carga operativa por plan, tasa de conversión de la tienda, picos de tráfico por día de semana, upgrades/downgrades de suscripción, y estacionalidad de facturación mensual y semanal.

## Estructura del repositorio

```
magicdb-streaming-analytics/
├── README.md
├── LICENSE
├── docs/
│   ├── 01-caso-modelo-conceptual.pdf
│   ├── 02-modelo-fisico-carga-datos.pdf
│   └── 03-capa-acceso-dashboard.pdf
├── sql/
│   ├── SQLQuery1.sql
│   ├── SQLQuery2.sql
│   ├── SQLQuery3.sql
│   ├── SQLQuery4(vistas).sql
│   ├── SQLQuery5(indices).sql
│   └── SQLQuery6(SP).sql
├── dashboard/
│   └── magicdb-dashboard.json
└── screenshots/
    ├── dashboard-overview.png
    └── er-diagram.png
```

## Cómo correrlo

Requiere SQL Server (local o en contenedor Docker) y, opcionalmente, Grafana para levantar el dashboard.

```bash
# 1. Conectarse al motor (no a una base específica) y ejecutar en orden:
sqlcmd -S localhost,1434 -i sql/SQLQuery1.sql
sqlcmd -S localhost,1434 -i sql/SQLQuery2.sql
sqlcmd -S localhost,1434 -i sql/SQLQuery3.sql
sqlcmd -S localhost,1434 -i sql/SQLQuery4(vistas).sql
sqlcmd -S localhost,1434 -i sql/SQLQuery5(indices).sql
sqlcmd -S localhost,1434 -i sql/SQLQuery6(SP).sql
```

> Los scripts deben ejecutarse en este orden por dependencias de claves foráneas. Si se vuelve a correr `01-create-database.sql`, la base se elimina y recrea desde cero, por lo que hay que repetir del paso 2 en adelante.

Para el dashboard: levantar Grafana, agregar SQL Server como data source apuntando al mismo motor, e importar `dashboard/magicdb-dashboard.json`.

## Datos sintéticos

La carga de datos se generó con T-SQL procedural (`WHILE`, `RAND()`, `NEWID()`) directamente en el motor, en lugar de Python + Faker, para no depender de configuración de entorno externa y para que cualquier violación de `CHECK`/FK/`UNIQUE` se detecte en el momento exacto de la inserción.

Los volúmenes y distribuciones no son uniformes a propósito — reflejan comportamiento realista de adopción de un SaaS (mayoría de usuarios en planes gratuitos, conversión de tienda forzada al 40%, donaciones concentradas en montos bajos con una cola de donaciones grandes, actividad de streaming concentrada en horario nocturno) para que el dashboard muestre patrones interpretables en lugar de promedios planos. Ningún dato representa información real de usuarios ni de ninguna plataforma existente.

| Tabla | Filas |
|---|---|
| Usuarios | 60 |
| Suscripciones | ~79 |
| ComprasAssets | 1.050 |
| AlertasEventos | 1.500 |

## Autora

**Julieta Luján Barrios** — Ingeniería en Inteligencia Artificial, 3er año, UNSTA (2026).

Materia: Bases de Datos — Prof. Ing. Sosa, Leandro Nicolás.

## Licencia

Este proyecto está bajo licencia MIT — ver [LICENSE](LICENSE) para más detalles.
