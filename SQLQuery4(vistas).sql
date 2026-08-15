-- TRABAJO PRÁCTICO FINAL INTEGRADOR - BASES DE DATOS
-- DESCRIPCIÓN: Función escalar auxiliar + 8 vistas analíticas. Cada vista responde exactamente a una pregunta de negocio. (Ninguna es un SELECT * FROM Tabla envuelto en CREATE VIEW).

USE MagicDB;
GO
 

-- PARTE 0: FUNCIÓN ESCALAR DE USUARIO
-- fn_SemanaMes

-- PROPÓSITO: encapsula la lógica de clasificación de un día del mes en una de las cuatro semanas (1ª a 4ª). Esta lógica aparece de forma idéntica en dos vistas distintas: v_VentasPorSemanaMes y v_SuscripcionesPorSemanaMes.

-- POR QUÉ SE EXTRAE A UNA FUNCIÓN:
--   Si el criterio de segmentación semanal cambia (por ejemplo, pasar de bloques de 7 días a semanas ISO), sin esta función habría que modificar dos vistas por separado con riesgo de inconsistencia entre ellas.
--   Con la función, el cambio se hace en un único lugar y ambas vistas lo heredan automáticamente. Este es exactamente el principio DRY (Don't Repeat Yourself) aplicado al modelo de datos.

-- USO: dbo.fn_SemanaMes(FechaCompra) --> devuelve 1, 2, 3 o 4.

IF OBJECT_ID('fn_SemanaMes', 'FN') IS NOT NULL DROP FUNCTION fn_SemanaMes; -- OBJECT_ID devuelve NULL si la función no existe, evitando error al intentar borrarla. Y FN indica que es una función escalar de usuario.
GO
 
CREATE FUNCTION fn_SemanaMes (@Fecha DATETIME2)
RETURNS INT
AS
BEGIN
    RETURN
        CASE
            WHEN DATEPART(DAY, @Fecha) <= 7  THEN 1  -- Primera semana: días 1 al 7
            WHEN DATEPART(DAY, @Fecha) <= 14 THEN 2  -- Segunda semana: días 8 al 14
            WHEN DATEPART(DAY, @Fecha) <= 21 THEN 3  -- Tercera semana: días 15 al 21
            ELSE                                  4  -- Cuarta semana+: días 22 al 31
        END;
END;
GO 
 

-- PARTE 1: VISTAS ANALÍTICAS (8 VISTAS)


-- Vista 1: v_PopularidadAssetsTienda
-- RESPONDE: Pregunta de negocio 1 — ¿qué tipos de recursos digitales prefieren comprar los streamers y cuál es el producto individual más vendido?

-- POR QUÉ VISTA Y NO SP: el resultado no depende de parámetros del usuario; siempre muestra el estado completo del catálogo.
-- Una vista permite que el dashboard la consulte con SELECT + ORDER BY según la dimensión que quiera mostrar (por cantidad, por ingresos, por tipo), sin necesidad de un SP distinto para cada combinación.

-- TÉCNICA: LEFT JOIN en lugar de INNER JOIN para que los assets con cero compras también aparezcan en el resultado (el INNER los ocultaría, lo que daría una imagen incompleta del catálogo).
IF OBJECT_ID('v_PopularidadAssetsTienda', 'V') IS NOT NULL
    DROP VIEW v_PopularidadAssetsTienda;
GO
 
CREATE VIEW v_PopularidadAssetsTienda AS
SELECT
    ast.IdAsset,
    ast.CodigoAsset,
    ast.Nombre                        AS NombreAsset, -- Alias para mejor legibilidad en el dashboard
    ast.TipoAsset,
    ast.Precio,
    -- ISNULL para que los assets sin compras muestren 0 en lugar de NULL
    COUNT(ca.IdCompraAsset)           AS CantidadAdquisiciones,
    ISNULL(SUM(ca.Monto), 0.00)       AS TotalIngresosGenerados
FROM AssetsTienda ast
-- LEFT JOIN: incluye assets activos aunque todavía no hayan sido comprados
LEFT JOIN ComprasAssets ca ON ast.IdAsset = ca.IdAsset
GROUP BY ast.IdAsset, ast.CodigoAsset, ast.Nombre, ast.TipoAsset, ast.Precio;
GO
 
 
-- Vista 2: v_RequestAlertasPorSuscripcion
-- RESPONDE: Pregunta de negocio 2 — ¿qué porcentaje de los eventos de alerta generados en vivo corresponde a cada nivel de suscripción?

-- TÉCNICA 1 — CTE (UltimaSuscripcionPorUsuario):
--   Un usuario con historial de upgrades o downgrades tiene más de una fila en Suscripciones. Si se joinea directamente con esa tabla, cada evento de alerta del usuario se contaría N veces (una por cada suscripción que tuvo), produciendo porcentajes incorrectos. 
--   El CTE resuelve esto tomando solo la suscripción más reciente de cada usuario mediante ROW_NUMBER() OVER (PARTITION BY IdUsuario ORDER BY FechaInicio DESC) y filtrando rn = 1.
--   Este es un uso genuino del CTE: simplifica una lógica que sin él requeriría una subconsulta correlacionada anidada en el FROM, más difícil de leer.

-- TÉCNICA 2 — Función de ventana (SUM() OVER()):
--   SUM(COUNT(*)) OVER() calcula el total global de alertas en la misma pasada que el GROUP BY, sin necesidad de una subconsulta separada. Esto permite calcular el porcentaje de cada plan sobre el total en una sola consulta.

-- TÉCNICA 3 — Tablas normalizadas:
--   El filtro de estado ya no usa strings directos ('active', 'past_due').
--   Se joinea con EstadosSuscripcion y se filtra por DescripcionEstadoSuscripcion, respetando el diseño normalizado de la base.
IF OBJECT_ID('v_RequestAlertasPorSuscripcion', 'V') IS NOT NULL
    DROP VIEW v_RequestAlertasPorSuscripcion;
GO
 
CREATE VIEW v_RequestAlertasPorSuscripcion AS
WITH UltimaSuscripcionPorUsuario AS (
    -- CTE que resuelve el problema de fan-out:
    -- Para cada usuario, ROW_NUMBER() numera sus suscripciones de la más reciente (1) a la más antigua. El filtro rn = 1 en el JOIN externo garantiza que cada usuario aporta exactamente una fila, eliminando el riesgo de conteo múltiple de eventos.

    SELECT
        s.IdUsuario,
        s.IdPlan,
        s.IdEstadoSuscripcion,
        ROW_NUMBER() OVER (
            PARTITION BY s.IdUsuario     -- reinicia el conteo para cada usuario
            ORDER BY s.FechaInicio DESC  -- la más reciente queda con rn = 1
        ) AS rn
    FROM Suscripciones s
)
SELECT
    u.IdPlan                                                           AS PlanSuscripcion,
    p.Nombre                                                           AS NombrePlan,
    COUNT(ae.IdAlertaEvento)                                           AS CantidadAlertasProcesadas,
    -- FUNCIÓN DE VENTANA: SUM(COUNT(*)) OVER() calcula el total global de alertas sin agrupar, en la misma consulta. Permite obtener el porcentaje exacto de cada plan sobre el total de forma dinámica.
    CAST( -- CAST para forzar aritmética decimal y evitar truncamiento por división entera
        COUNT(ae.IdAlertaEvento) * 100.0
        / SUM(COUNT(ae.IdAlertaEvento)) OVER()
    AS DECIMAL(5,2))                                                   AS PorcentajeDelTotalRequests -- decimal(5,2) para mostrar hasta 2 decimales en el porcentaje
FROM AlertasEventos ae
INNER JOIN AlertasConfiguraciones ac  ON ae.IdAlertaConfiguracion = ac.IdAlertaConfiguracion
INNER JOIN Proyectos proj             ON ac.IdProyecto = proj.IdProyecto
-- JOIN con el CTE: rn = 1 asegura una sola suscripción por usuario
INNER JOIN UltimaSuscripcionPorUsuario u ON proj.IdUsuario = u.IdUsuario AND u.rn = 1
INNER JOIN Planes p                   ON u.IdPlan = p.IdPlan
-- JOIN con tabla normalizada: reemplaza el filtro directo sobre strings
INNER JOIN EstadosSuscripcion es      ON u.IdEstadoSuscripcion = es.IdEstadoSuscripcion
-- Filtramos por estados vigentes (excluimos 'canceled') usando la tabla referencial
WHERE es.DescripcionEstadoSuscripcion IN ('active', 'past_due', 'trialing')
GROUP BY u.IdPlan, p.Nombre;
GO
 
 
-- Vista 3: v_ConversionCompradoresAssets
-- RESPONDE: Pregunta de negocio 3 — ¿qué porcentaje de los usuarios registrados realiza al menos una compra en la tienda de assets?

-- TÉCNICA — CTE (doble CTE independiente):
--   Se usan dos CTEs en secuencia:
--     - CTE_UsuariosTotales: cuenta todos los usuarios registrados.
--     - CTE_CompradoresUnicos: cuenta los usuarios distintos que compraron al menos una vez (DISTINCT evita que un usuario con múltiples compras cuente más de una vez).
--   Ambos resultados se combinan en el SELECT final con un producto cartesiano controlado (FROM ... , ...) que funciona porque cada CTE devuelve exactamente una fila. Sin CTEs, esta lógica requeriría dos subconsultas anidadas en el SELECT, más difíciles de leer y mantener.
IF OBJECT_ID('v_ConversionCompradoresAssets', 'V') IS NOT NULL
    DROP VIEW v_ConversionCompradoresAssets;
GO
 
CREATE VIEW v_ConversionCompradoresAssets AS
WITH CTE_UsuariosTotales AS (
    -- Primer CTE: total de usuarios registrados en la plataforma.
    -- Se usa COUNT(*) sin filtros para incluir todos, incluso los que nunca compraron (que son precisamente los que reducen la tasa).
    SELECT COUNT(*) AS TotalRegistrados FROM Usuarios
),
CTE_CompradoresUnicos AS (
    -- Segundo CTE: usuarios distintos que compraron al menos un asset.
    -- DISTINCT es fundamental: sin él, un usuario con 50 compras contaría 50, no 1, inflando artificialmente el numerador del porcentaje.
    SELECT COUNT(DISTINCT IdUsuario) AS TotalCompradores FROM ComprasAssets
)
SELECT
    ut.TotalRegistrados                                              AS StreamersRegistrados,
    cu.TotalCompradores                                              AS StreamersCompradoresUnicos,
    -- División con 100.0 (no 100) para forzar aritmética decimal y evitar truncamiento por división entera (ej: 24/60 = 0 en aritmética entera).
    CAST((cu.TotalCompradores * 100.0) / ut.TotalRegistrados
        AS DECIMAL(5,2))                                             AS PorcentajeConversionTienda
-- Producto cartesiano controlado: ambas CTEs devuelven exactamente 1 fila, por lo que el resultado final también tiene exactamente 1 fila.
FROM CTE_UsuariosTotales ut, CTE_CompradoresUnicos cu;
GO
 
 
-- Vista 4: v_PicosTraficoAlertas
-- RESPONDE: Pregunta de negocio 4 — ¿qué días de la semana concentran mayor actividad de alertas en la plataforma?

-- TÉCNICA — CTE en dos etapas:
--   El cálculo del promedio por día de semana no puede hacerse en un solo GROUP BY porque requiere dos niveles de agrupación:
--     Nivel 1 (CTE_AlertasPorDiaCalendario): agrupa por fecha real (un día específico del calendario, ej. 2025-10-15) y día de semana, contando las alertas de cada jornada concreta.
--     Nivel 2 (SELECT final): agrupa por número de día de semana (1=Domingo, 7=Sábado) y promedia los totales diarios de nivel 1.
--   Sin el CTE, este doble nivel de agrupación requeriría una subconsulta en el FROM, que es sintácticamente equivalente pero menos legible.
-- POR QUÉ PROMEDIO Y NO SUMA:
--   La suma acumularía alertas a lo largo del tiempo histórico (un miércoles con 6 meses de datos suma mucho más que un miércoles con 1 semana). El promedio de alertas por día normaliza el volumen histórico y refleja la actividad real de cada día de semana independientemente del período analizado.
IF OBJECT_ID('v_PicosTraficoAlertas', 'V') IS NOT NULL
    DROP VIEW v_PicosTraficoAlertas;
GO
 
CREATE VIEW v_PicosTraficoAlertas AS
WITH CTE_AlertasPorDiaCalendario AS (
    -- Nivel 1: cuenta alertas por cada fecha concreta del calendario.
    -- CAST(FechaEvento AS DATE) elimina la componente horaria para que todas las alertas del mismo día queden en el mismo grupo.
    SELECT
        CAST(ae.FechaEvento AS DATE)          AS FechaReal,
        DATEPART(WEEKDAY, ae.FechaEvento)     AS DiaSemanaNumero,
        COUNT(ae.IdAlertaEvento)              AS TotalAlertasDelDia
    FROM AlertasEventos ae
    GROUP BY
        CAST(ae.FechaEvento AS DATE),
        DATEPART(WEEKDAY, ae.FechaEvento)
)
-- Nivel 2: promedia los totales diarios de cada día de semana.
SELECT
    DiaSemanaNumero,
    -- CASE para convertir el número de día (WEEKDAY) al nombre en español.
    -- En SQL Server, DATEPART(WEEKDAY) depende del SET DATEFIRST configurado.
    -- Con DATEFIRST = 7 (en español): 1=Domingo, 2=Lunes, ..., 7=Sábado.
    CASE DiaSemanaNumero
        WHEN 1 THEN 'Domingo'
        WHEN 2 THEN 'Lunes'
        WHEN 3 THEN 'Martes'
        WHEN 4 THEN 'Miercoles'
        WHEN 5 THEN 'Jueves'
        WHEN 6 THEN 'Viernes'
        WHEN 7 THEN 'Sabado'
    END                                       AS DiaSemanaNombre,
    -- Promedio normalizado: cantidad de alertas por jornada real de ese día.
    AVG(TotalAlertasDelDia)                   AS PromedioAlertasPorDia,
    -- Total acumulado histórico: útil como referencia absoluta en el dashboard.
    SUM(TotalAlertasDelDia)                   AS TotalAlertasHistoricas
FROM CTE_AlertasPorDiaCalendario
GROUP BY DiaSemanaNumero;
GO
 
  
-- Vista 5: v_UpgradesDowngradesSuscripciones
-- RESPONDE: Pregunta de negocio 5 — ¿cuántos usuarios cambian de plan y en qué dirección lo hacen: hacia planes superiores o inferiores?

-- TÉCNICA — CTE + LAG() (función de ventana):
--   LAG(columna) OVER (PARTITION BY IdUsuario ORDER BY FechaInicio) devuelve el valor de la fila anterior dentro del mismo usuario, ordenada por fecha.
--   Esto permite comparar cada suscripción con la inmediatamente anterior:
--     - Si PrecioActual > PrecioAnterior --> el usuario subió de plan (upgrade).
--     - Si PrecioActual < PrecioAnterior --> el usuario bajó de plan (downgrade).
--     - Si PrecioActual = PrecioAnterior pero el plan cambió --> cambio lateral (por ejemplo, entre dos planes con el mismo precio).
--   El CTE encapsula el cálculo de LAG para que el SELECT externo pueda aplicar los CASE de clasificación sobre los valores ya calculados, sin repetir la expresión de ventana en cada condición.
--   WHERE PlanAnterior IS NOT NULL filtra la primera suscripción de cada usuario (la que no tiene fila previa, por lo que LAG devuelve NULL).
--   Esa primera suscripción no representa un cambio de plan sino el alta inicial.
IF OBJECT_ID('v_UpgradesDowngradesSuscripciones', 'V') IS NOT NULL
    DROP VIEW v_UpgradesDowngradesSuscripciones;
GO
 
CREATE VIEW v_UpgradesDowngradesSuscripciones AS
WITH CTE_HistorialCambios AS (
    SELECT
        s.IdUsuario,
        s.IdPlan                                                           AS PlanActual,
        p_act.PrecioMensual                                                AS PrecioActual,
        -- FUNCIÓN DE VENTANA LAG():
        --   Accede al valor de IdPlan de la fila anterior del mismo usuario, ordenada por FechaInicio. 
        --PARTITION BY garantiza que el "anterior" siempre sea del mismo usuario, nunca de otro.
        LAG(s.IdPlan)          OVER (PARTITION BY s.IdUsuario ORDER BY s.FechaInicio) AS PlanAnterior, -- LAG es para comparar con la suscripción previa del mismo usuario
        LAG(p_act.PrecioMensual) OVER (PARTITION BY s.IdUsuario ORDER BY s.FechaInicio) AS PrecioAnterior
    FROM Suscripciones s
    INNER JOIN Planes p_act ON s.IdPlan = p_act.IdPlan
)
SELECT
    -- COUNT con filtro CASE: cuenta solo las filas que cumplen cada condición.
    -- Es equivalente a tres consultas separadas con WHERE, pero en una sola pasada.
    COUNT(CASE WHEN PrecioActual > PrecioAnterior THEN 1 END)                  AS CantidadUpgrades,
    COUNT(CASE WHEN PrecioActual < PrecioAnterior THEN 1 END)                  AS CantidadDowngrades,
    COUNT(CASE WHEN PrecioActual = PrecioAnterior
               AND PlanActual <> PlanAnterior THEN 1 END)                      AS CambiosMismoPrecio,
    COUNT(*)                                                                   AS TotalCambiosRegistrados
FROM CTE_HistorialCambios
-- Filtra la primera suscripción de cada usuario: LAG devuelve NULL cuando no hay fila previa, lo que significa que ese registro es el alta inicial, no un cambio.
WHERE PlanAnterior IS NOT NULL;
GO
 
 
-- Vista 6: v_TendenciaVentasMensual
-- RESPONDE: Pregunta de negocio 6 — ¿en qué meses del año se registra el pico máximo y el mínimo de facturación por venta de assets?

-- TÉCNICA — Función de ventana RANK() OVER():
--   RANK() asigna una posición a cada mes según su facturación total, de mayor a menor. A diferencia de ROW_NUMBER(), RANK() asigna el mismo número a filas con el mismo valor (empate), dejando un "hueco" en la posición siguiente. Esto es correcto para un ranking de negocio: si febrero y marzo facturan lo mismo, ambos deben ser "1er lugar", no uno arbitrariamente primero.
--   El dashboard puede identificar el pico (RANK = 1) y el mínimo (RANK = MAX) directamente sin lógica adicional.
-- AGRUPACIÓN por AÑO y MES: permite ver la evolución temporal (el mismo mes en distintos años puede comportarse diferente) además del ranking agregado.
IF OBJECT_ID('v_TendenciaVentasMensual', 'V') IS NOT NULL
    DROP VIEW v_TendenciaVentasMensual;
GO
 
CREATE VIEW v_TendenciaVentasMensual AS
SELECT
    YEAR(ca.FechaCompra)                      AS Anio,
    MONTH(ca.FechaCompra)                     AS NumeroMes,
    -- Nombre del mes en español para mejor legibilidad en el dashboard.
    CASE MONTH(ca.FechaCompra)
        WHEN 1  THEN 'Enero'      WHEN 2  THEN 'Febrero'
        WHEN 3  THEN 'Marzo'      WHEN 4  THEN 'Abril'
        WHEN 5  THEN 'Mayo'       WHEN 6  THEN 'Junio'
        WHEN 7  THEN 'Julio'      WHEN 8  THEN 'Agosto'
        WHEN 9  THEN 'Septiembre' WHEN 10 THEN 'Octubre'
        WHEN 11 THEN 'Noviembre'  WHEN 12 THEN 'Diciembre'
    END                                       AS NombreMes,
    COUNT(ca.IdCompraAsset)                   AS CantidadVentas,
    SUM(ca.Monto)                             AS TotalFacturado,
    -- FUNCIÓN DE VENTANA RANK():
    --   Ordena los meses de mayor a menor facturación.
    --   RANK() (y no ROW_NUMBER()) para manejar correctamente los empates.
    RANK() OVER (ORDER BY SUM(ca.Monto) DESC) AS RankingVentasMonto
FROM ComprasAssets ca
GROUP BY YEAR(ca.FechaCompra), MONTH(ca.FechaCompra);
GO
 
 
-- Vista 7: v_VentasPorSemanaMes
-- RESPONDE: Pregunta de negocio 7 — ¿en qué semana del mes se factura más en la tienda de assets?

-- TÉCNICA 1 — Función escalar fn_SemanaMes():
--   En lugar de repetir el bloque CASE WHEN DATEPART(DAY) <= 7 THEN 1 ... (que también aparece en v_SuscripcionesPorSemanaMes), se llama a la función fn_SemanaMes() creada al inicio del script. Esto centraliza la lógica de segmentación semanal: si el criterio cambia, se modifica solo la función y ambas vistas se actualizan automáticamente.

-- TÉCNICA 2 — Función de ventana RANK() OVER():
--   Igual que en v_TendenciaVentasMensual, RANK() asigna posición a cada semana por su facturación total. El dashboard puede identificar directamente cuál es la semana de mayor conversión (RANK = 1).
IF OBJECT_ID('v_VentasPorSemanaMes', 'V') IS NOT NULL
    DROP VIEW v_VentasPorSemanaMes;
GO
 
CREATE VIEW v_VentasPorSemanaMes AS
SELECT
    -- Llamada a la función escalar: reemplaza el bloque CASE repetido.
    -- dbo. es obligatorio para funciones escalares de usuario.
    dbo.fn_SemanaMes(ca.FechaCompra)              AS NumeroSemanaMes,
    CASE dbo.fn_SemanaMes(ca.FechaCompra)
        WHEN 1 THEN 'Primera Semana'
        WHEN 2 THEN 'Segunda Semana'
        WHEN 3 THEN 'Tercera Semana'
        ELSE        'Cuarta Semana+'
    END                                           AS SemanaMesNombre,
    COUNT(ca.IdCompraAsset)                       AS CantidadVentas,
    SUM(ca.Monto)                                 AS TotalFacturado,
    -- FUNCIÓN DE VENTANA RANK(): posiciona cada semana por facturación.
    RANK() OVER (ORDER BY SUM(ca.Monto) DESC)     AS RankingVentas
FROM ComprasAssets ca
GROUP BY dbo.fn_SemanaMes(ca.FechaCompra);
GO
 
 
-- Vista 8: v_SuscripcionesPorSemanaMes
-- RESPONDE: Pregunta de negocio 8 — ¿en qué semanas del mes los usuarios tienden a activar nuevas suscripciones?

-- TÉCNICA 1— Función escalar fn_SemanaMes():
--   Mismo razonamiento que en v_VentasPorSemanaMes. El uso de la función garantiza consistencia en la definición de "semana del mes" entre ambas vistas: si el dashboard compara semanas de compras con semanas de suscripciones, ambas usan exactamente el mismo criterio de segmentación.

-- TÉCNICA 2 — Función de ventana RANK() OVER():
--   Posiciona cada semana por volumen de suscripciones nuevas activadas.
--   El dashboard puede identificar el momento de mayor conversión del mes para orientar campañas de captación y onboarding.
IF OBJECT_ID('v_SuscripcionesPorSemanaMes', 'V') IS NOT NULL
    DROP VIEW v_SuscripcionesPorSemanaMes;
GO
 
CREATE VIEW v_SuscripcionesPorSemanaMes AS
SELECT
    -- Función escalar: misma lógica de segmentación que v_VentasPorSemanaMes.
    dbo.fn_SemanaMes(s.FechaInicio)               AS NumeroSemanaMes,
    CASE dbo.fn_SemanaMes(s.FechaInicio)
        WHEN 1 THEN 'Primera Semana'
        WHEN 2 THEN 'Segunda Semana'
        WHEN 3 THEN 'Tercera Semana'
        ELSE        'Cuarta Semana+'
    END                                           AS SemanaMesNombre,
    COUNT(s.IdSuscripcion)                        AS CantidadSuscripciones,
    -- FUNCIÓN DE VENTANA RANK(): posiciona cada semana por volumen de altas.
    RANK() OVER (ORDER BY COUNT(s.IdSuscripcion) DESC) AS RankingSuscripciones
FROM Suscripciones s
GROUP BY dbo.fn_SemanaMes(s.FechaInicio);
GO
 
 

PRINT 'Función escalar creada: fn_SemanaMes';
PRINT '--------------------------------------------------------';
PRINT 'Vistas creadas (8 en total):';
PRINT '  1. v_PopularidadAssetsTienda --> P. negocio 1';
PRINT '  2. v_RequestAlertasPorSuscripcion --> P. negocio 2';
PRINT '  3. v_ConversionCompradoresAssets --> P. negocio 3';
PRINT '  4. v_PicosTraficoAlertas --> P. negocio 4';
PRINT '  5. v_UpgradesDowngradesSuscripciones --> P. negocio 5';
PRINT '  6. v_TendenciaVentasMensual --> P. negocio 6';
PRINT '  7. v_VentasPorSemanaMes --> P. negocio 7';
PRINT '  8. v_SuscripcionesPorSemanaMes --> P. negocio 8';
GO