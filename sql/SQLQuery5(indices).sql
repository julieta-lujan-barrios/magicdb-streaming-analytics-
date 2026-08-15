-- TRABAJO PRÁCTICO FINAL INTEGRADOR - BASES DE DATOS
-- DESCRIPCIÓN: 3 índices no agrupados (NONCLUSTERED). Se incluyen porque cada uno está atado a una consulta concreta de la capa de acceso y su ausencia tiene un impacto medible en el plan de ejecución.

-- REGLA APLICADA:
--   Si no se puede identificar exactamente qué consulta optimiza el índice y por qué, el índice no se crea. 
--   Los índices tienen costo de escritura: cada INSERT, UPDATE o DELETE sobre la tabla base debe actualizar también todos sus índices. Por eso no agregamos índices injustificados.

-- NOTA SOBRE ÍNDICES AUTOMÁTICOS:
--   Los índices de este script cubren únicamente patrones de acceso analítico que los índices automáticos de SQL no cubren.

USE MagicDB;
GO


-- ÍNDICE 1: IX_AlertasEventos_FechaEvento

-- CONSULTAS QUE OPTIMIZA:
--   a) v_PicosTraficoAlertas:
--      El CTE interno hace GROUP BY CAST(FechaEvento AS DATE) sobre toda la tabla AlertasEventos. Sin índice, el motor hace un SCAN completo de las 1500+ filas para extraer la componente de fecha. Con el índice, puede hacer un SCAN ordenado sobre las páginas del índice (mucho más eficiente que leer la tabla completa).
--   b) sp_ReporteDonacionesRango:
--      Si en el futuro se agrega un parámetro de rango de fechas al SP, este índice permite un SEEK directo al rango sin SCAN completo.

-- IMPACTO ESPERADO:
--   v_PicosTraficoAlertas pasa de TABLE SCAN a INDEX SCAN ordenado.
--   Queries con filtro WHERE FechaEvento BETWEEN pasan a INDEX SEEK.
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_AlertasEventos_FechaEvento'
      AND object_id = OBJECT_ID('AlertasEventos')
)
    DROP INDEX IX_AlertasEventos_FechaEvento ON AlertasEventos;
GO

CREATE NONCLUSTERED INDEX IX_AlertasEventos_FechaEvento
    ON AlertasEventos (FechaEvento)
    -- Columnas incluidas: El motor puede resolver la consulta completa solo con el índice, sin tocar la tabla base.
    INCLUDE (IdAlertaConfiguracion, IdUsuario, ValorDonado);
GO


-- ÍNDICE 2: IX_ComprasAssets_FechaCompra

-- CONSULTAS QUE OPTIMIZA:
--   a) v_TendenciaVentasMensual:
--      Hace GROUP BY YEAR(FechaCompra), MONTH(FechaCompra) sobre las 1050+ filas de ComprasAssets. Sin índice, SCAN completo de la tabla en cada consulta al dashboard. Con índice, SCAN ordenado sobre las páginas hoja.
--   b) v_VentasPorSemanaMes:
--      Misma tabla, mismo patrón: agrupa por fn_SemanaMes(FechaCompra). Comparte el beneficio del índice con v_TendenciaVentasMensual.
--   c) sp_BuscarComprasAssets(@FechaInicio, @FechaFin, @TipoAsset):
--      El SP filtra WHERE FechaCompra BETWEEN @FechaInicio AND @FechaFin. Sin índice, SCAN completo de 1050+ filas por cada llamada desde el dashboard. Con índice, SEEK directo al rango de fechas solicitado.
--      Este es el caso de mayor impacto: un SP con parámetro de rango temporal es exactamente el patrón de uso que más se beneficia de un índice sobre la columna de fecha.

-- POR QUÉ INCLUDE (IdUsuario, IdAsset, Monto):
--   sp_BuscarComprasAssets proyecta IdUsuario, IdAsset y Monto además de FechaCompra. Con estas columnas en INCLUDE, el SP se resuelve completamente desde el índice sin búsqueda a la tabla base.

-- IMPACTO ESPERADO:
--   sp_BuscarComprasAssets pasa de TABLE SCAN a INDEX SEEK + lectura desde el índice cubriente. Las vistas analíticas pasan de TABLE SCAN a INDEX SCAN ordenado (más eficiente al tener menos páginas que la tabla).
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_ComprasAssets_FechaCompra'
      AND object_id = OBJECT_ID('ComprasAssets')
)
    DROP INDEX IX_ComprasAssets_FechaCompra ON ComprasAssets;
GO

CREATE NONCLUSTERED INDEX IX_ComprasAssets_FechaCompra
    ON ComprasAssets (FechaCompra)
    -- Columnas incluidas: permiten que sp_BuscarComprasAssets y las vistas analíticas resuelvan sus proyecciones sin Key Lookup a la tabla base.
    INCLUDE (IdUsuario, IdAsset, Monto);
GO


-- ÍNDICE 3: IX_Suscripciones_IdUsuario_FechaInicio

-- CONSULTAS QUE OPTIMIZA:
--   a) v_UpgradesDowngradesSuscripciones (y su CTE interno):
--      Usa LAG() OVER (PARTITION BY IdUsuario ORDER BY FechaInicio). Una función de ventana con PARTITION BY + ORDER BY requiere que los datos estén ordenados por (IdUsuario, FechaInicio). Sin índice, el motor agrega un operador SORT explícito al plan de ejecución, que materializa toda la tabla en memoria y la ordena. Con este índice, los datos ya vienen ordenados por (IdUsuario, FechaInicio) desde el propio índice, eliminando completamente el operador SORT del plan.
--   b) v_RequestAlertasPorSuscripcion (CTE UltimaSuscripcionPorUsuario):
--      Usa ROW_NUMBER() OVER (PARTITION BY IdUsuario ORDER BY FechaInicio DESC). El índice provee los datos ya ordenados en el orden que necesita la función de ventana, evitando el operador SORT.
--   c) sp_FichaRendimientoStreamer:
--      La subconsulta interna hace TOP 1 ORDER BY FechaInicio DESC WHERE IdUsuario = @IdUsuario. Con este índice, el motor hace SEEK directo al IdUsuario solicitado y lee la primera fila en orden descendente de FechaInicio, sin SCAN completo de la tabla.

-- POR QUÉ EL ORDEN DE COLUMNAS ES (IdUsuario, FechaInicio) Y NO AL REVÉS:
--   La clave de un índice compuesto se usa de izquierda a derecha. Poner IdUsuario primero permite SEEK por usuario específico (filtro de igualdad) y luego recorrer las fechas en orden dentro de ese usuario. Si estuviera FechaInicio primero, un SEEK por IdUsuario no podría usar el índice.

-- POR QUÉ INCLUDE (IdPlan, IdEstadoSuscripcion):
--   Las consultas que usan este índice también proyectan IdPlan e IdEstadoSuscripcion. Con ellas en INCLUDE, el índice es cubriente para v_UpgradesDowngradesSuscripciones y v_RequestAlertasPorSuscripcion, eliminando Key Lookups a la tabla base.

-- IMPACTO ESPERADO:
--   Elimina el operador SORT del plan de ejecución en todas las funciones de ventana sobre Suscripciones. sp_FichaRendimientoStreamer pasa de TABLE SCAN a INDEX SEEK.
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Suscripciones_IdUsuario_FechaInicio'
      AND object_id = OBJECT_ID('Suscripciones')
)
    DROP INDEX IX_Suscripciones_IdUsuario_FechaInicio ON Suscripciones;
GO

CREATE NONCLUSTERED INDEX IX_Suscripciones_IdUsuario_FechaInicio
    ON Suscripciones (IdUsuario, FechaInicio)
    -- Columnas incluidas: cubren las proyecciones de las vistas que usan este índice, evitando Key Lookups a la tabla base.
    INCLUDE (IdPlan, IdEstadoSuscripcion);
GO


-- VERIFICACIÓN POST-CREACIÓN
-- Muestra todos los índices de las tablas principales para confirmar que los tres índices fueron creados correctamente.
SELECT
    OBJECT_NAME(i.object_id)   AS Tabla,
    i.name                     AS Indice,
    i.type_desc                AS Tipo,
    i.is_unique                AS Unico,
    -- Lista las columnas que forman la clave del índice
    STRING_AGG(
        CASE ic.is_included_column
            WHEN 0 THEN c.name
        END, ', '
    ) WITHIN GROUP (ORDER BY ic.key_ordinal)  AS ColumnasClave,
    -- Lista las columnas incluidas (INCLUDE)
    STRING_AGG(
        CASE ic.is_included_column
            WHEN 1 THEN c.name
        END, ', '
    )                                          AS ColumnasIncluidas
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id
                                AND i.index_id  = ic.index_id
INNER JOIN sys.columns c        ON ic.object_id = c.object_id
                                AND ic.column_id = c.column_id
WHERE OBJECT_NAME(i.object_id) IN (
    'AlertasEventos', 'ComprasAssets', 'Suscripciones'
)
  AND i.name IS NOT NULL
GROUP BY i.object_id, i.name, i.type_desc, i.is_unique
ORDER BY Tabla, Indice;
GO

PRINT 'Índices creados (3 en total):';
PRINT '  1. IX_AlertasEventos_FechaEvento';
PRINT '     Optimiza: v_PicosTraficoAlertas, sp_ReporteDonacionesRango';
PRINT '  2. IX_ComprasAssets_FechaCompra';
PRINT '     Optimiza: v_TendenciaVentasMensual, v_VentasPorSemanaMes, sp_BuscarComprasAssets';
PRINT '  3. IX_Suscripciones_IdUsuario_FechaInicio';
PRINT '     Optimiza: v_UpgradesDowngradesSuscripciones (elimina SORT), v_RequestAlertasPorSuscripcion, sp_FichaRendimientoStreamer';
GO
