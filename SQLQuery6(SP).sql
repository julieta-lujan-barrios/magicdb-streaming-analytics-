-- TRABAJO PRÁCTICO FINAL INTEGRADOR - BASES DE DATOS
-- DESCRIPCIÓN: 3 stored procedures con parámetros funcionales. Complementan las vistas de SQLQuery4(vistas).sql: donde una vista siempre devuelve el estado completo de la base, un SP permite filtrar, acotar y parametrizar la consulta según lo que necesita el usuario del dashboard en cada momento.

-- ¿Cuándo SP y no vista?
--   - Cuando el resultado depende de parámetros que el usuario provee (rangos de fecha, montos, IDs).
--   - Cuando se necesita validación de entrada (RAISERROR si los parámetros son inválidos o el registro no existe).
--   - Cuando la lógica es demasiado compleja para una vista (múltiples result sets, lógica condicional, variables intermedias).

-- NOTA SOBRE LA NORMALIZACIÓN:
--   Los tres SPs referencian EstadosSuscripcion y TiposAlerta a través de JOINs, nunca comparando directamente contra strings en las columnas Estado o TipoAlerta (que ya no existen en el diseño normalizado).

USE MagicDB;
GO


-- STORED PROCEDURE 1: sp_BuscarComprasAssets

-- PROPÓSITO:
--   Permite al dashboard filtrar transacciones de la tienda de assets por rango de fechas y opcionalmente por tipo de asset. Devuelve el detalle de cada compra más un ranking de popularidad de assets dentro del período.

-- PARÁMETROS:
--   @FechaInicio DATETIME2 — fecha mínima de compra (inclusive).
--   @FechaFin    DATETIME2 — fecha máxima de compra (inclusive).
--   @TipoAsset   VARCHAR(50) — OPCIONAL (default NULL). Si se provee, filtra solo compras de assets de ese tipo ('image', 'video', 'audio' o 'font'). Si es NULL, devuelve todos los tipos.

-- POR QUÉ SP Y NO VISTA:
--   Una vista siempre devuelve todas las filas. Para un análisis de ventas en un período específico (ej. "¿qué se vendió más en el último mes?"), el dashboard necesita poder acotar el rango temporal. Un SP con parámetros resuelve esto; una vista no puede.

-- TÉCNICA 1 — CTE (RankingPorPeriodo):
--   Calcula el total de ventas y el monto facturado por asset dentro del rango de fechas filtrado. Esto requiere un nivel de agregación previo al resultado final. El CTE encapsula ese nivel intermedio para que el SELECT principal pueda aplicar RANK() sobre los totales ya calculados. Sin el CTE, RANK() sobre SUM() requeriría una subconsulta en el FROM o una expresión de ventana anidada, ambas más difíciles de leer.
-- TÉCNICA 2 — Función de ventana RANK() OVER():
--   Dentro del CTE, RANK() ordena los assets de mayor a menor cantidad de ventas en el período. A diferencia de ROW_NUMBER(), RANK() asigna el mismo puesto a assets con idéntica cantidad de ventas (empate real), lo que es semánticamente correcto para un ranking de popularidad.
-- TÉCNICA 3 — Parámetro opcional con valor DEFAULT NULL:
--   El filtro AND (@TipoAsset IS NULL OR ast.TipoAsset = @TipoAsset) es el patrón estándar para parámetros opcionales en T-SQL: si @TipoAsset es NULL (no fue provisto), la condición siempre es TRUE y no filtra. Si fue provisto, filtra por ese tipo. Un solo SP cubre ambos casos.

IF OBJECT_ID('sp_BuscarComprasAssets', 'P') IS NOT NULL
    DROP PROCEDURE sp_BuscarComprasAssets;
GO

CREATE PROCEDURE sp_BuscarComprasAssets
    @FechaInicio DATETIME2,
    @FechaFin    DATETIME2,
    @TipoAsset   VARCHAR(50) = NULL  -- Parámetro opcional: NULL = no filtrar por tipo, cualquier otro valor = filtrar por ese tipo específico
AS
BEGIN
    SET NOCOUNT ON; -- Evita que se devuelvan mensajes de "n filas afectadas" al cliente, lo cual es útil para SPs que devuelven resultados tabulares y no necesitan esos mensajes de estado.

    -- Validación de parámetros:
    -- FechaFin debe ser posterior o igual a FechaInicio. Si no lo es, la consulta devolvería cero filas sin advertencia, lo cual sería un resultado silenciosamente incorrecto. RAISERROR fuerza al dashboard a corregir los parámetros antes de continuar.
    IF @FechaFin < @FechaInicio
    BEGIN
        RAISERROR(
            'Parámetros inválidos: FechaFin debe ser mayor o igual a FechaInicio.',
            16,  -- Severidad 16: error de usuario, no del sistema
            1    -- State 1: identificador del punto de error dentro del SP
        );
        RETURN; -- RAISE ERROR detiene la ejecución del SP y devuelve el control al cliente (dashboard) con el mensaje de error. RETURN asegura que no se ejecute el resto del código.
    END

    -- Validación del tipo de asset:
    -- Si se proveyó un tipo, verificar que sea uno de los valores válidos. Como TipoAsset es VARCHAR en AssetsTienda, la validación se hace aquí.
    IF @TipoAsset IS NOT NULL
       AND @TipoAsset NOT IN ('image', 'video', 'audio', 'font')
    BEGIN
        RAISERROR(
            'TipoAsset inválido. Valores permitidos: image, video, audio, font.',
            16, 1
        );
        RETURN;
    END

    -- CTE: calcula el ranking de popularidad de assets en el período. Se separa en un CTE porque RANK() necesita operar sobre los totales agregados (SUM, COUNT) que el GROUP BY produce. Sin CTE habría que anidar la query en una subconsulta en el FROM, lo que reduce la legibilidad considerablemente, porque la función de ventana RANK() no puede aplicarse directamente sobre un GROUP BY sin encapsularlo primero.
    ;WITH RankingPorPeriodo AS (
        SELECT
            ca.IdAsset,
            COUNT(ca.IdCompraAsset)             AS VentasEnPeriodo,
            SUM(ca.Monto)                       AS MontoEnPeriodo,
            -- FUNCIÓN DE VENTANA RANK():
            --   Ordena los assets de mayor a menor cantidad de ventas en el período filtrado. El OVER() sin PARTITION BY aplica el ranking sobre todos los assets del resultado conjunto (no por grupos). Se usa RANK() (y no ROW_NUMBER()) para que assets con la misma cantidad de ventas compartan posición (empate real en popularidad).
            RANK() OVER (
                ORDER BY COUNT(ca.IdCompraAsset) DESC
            ) AS RankingPopularidad
        FROM ComprasAssets ca
        WHERE ca.FechaCompra BETWEEN @FechaInicio AND @FechaFin
          -- Parámetro opcional: si @TipoAsset es NULL, no filtra por tipo. La condición OR IS NULL hace que la cláusula sea siempre TRUE cuando el parámetro no fue provisto.
          AND (@TipoAsset IS NULL OR EXISTS (
              SELECT 1 FROM AssetsTienda ast2
              WHERE ast2.IdAsset = ca.IdAsset
                AND ast2.TipoAsset = @TipoAsset
          ))
        GROUP BY ca.IdAsset
    )
    -- SELECT principal: une el detalle de cada compra con el ranking calculado. El JOIN con RankingPorPeriodo añade las métricas agregadas del período a cada fila de compra individual.
    SELECT
        ca.IdCompraAsset,
        u.NombreUsuario                         AS Streamer,
        ast.Nombre                              AS NombreAsset,
        ast.TipoAsset,
        ca.Monto,
        ca.FechaCompra,
        -- Métricas del período provenientes del CTE:
        rpp.VentasEnPeriodo,
        rpp.MontoEnPeriodo,
        rpp.RankingPopularidad
    FROM ComprasAssets ca
    INNER JOIN Usuarios     u   ON ca.IdUsuario = u.IdUsuario
    INNER JOIN AssetsTienda ast ON ca.IdAsset   = ast.IdAsset
    -- JOIN con el CTE para traer el ranking calculado
    INNER JOIN RankingPorPeriodo rpp ON ca.IdAsset = rpp.IdAsset
    WHERE ca.FechaCompra BETWEEN @FechaInicio AND @FechaFin
      AND (@TipoAsset IS NULL OR ast.TipoAsset = @TipoAsset)
    ORDER BY ca.FechaCompra DESC;
END;
GO



-- STORED PROCEDURE 2: sp_FichaRendimientoStreamer

-- PROPÓSITO:
--   Genera una ficha consolidada con las métricas clave de actividad de un usuario específico: su plan actual, cantidad de proyectos, alertas configuradas, donaciones recibidas, assets comprados y monto invertido.
--   Permite al dashboard mostrar un perfil completo de un streamer al hacer clic sobre él en cualquier visualización.

-- PARÁMETROS:
--   @IdUsuario INT — ID del usuario a consultar.

-- POR QUÉ SP Y NO VISTA:
--   Una vista que cruzara todos estos datos para todos los usuarios sería extremadamente costosa (múltiples subconsultas correlacionadas sobre 60 usuarios × N filas cada una). Un SP que calcula esto para UN usuario específico es órdenes de magnitud más eficiente, y además puede validar que el usuario exista antes de ejecutar.

IF OBJECT_ID('sp_FichaRendimientoStreamer', 'P') IS NOT NULL
    DROP PROCEDURE sp_FichaRendimientoStreamer;
GO

CREATE PROCEDURE sp_FichaRendimientoStreamer
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Validación: el usuario debe existir.
    -- Se valida antes de ejecutar las subconsultas para evitar devolver una fila de NULLs en caso de ID inexistente, lo que podría interpretarse como un usuario real sin actividad.
    IF NOT EXISTS (SELECT 1 FROM Usuarios WHERE IdUsuario = @IdUsuario) -- SELECT 1 es una convención para EXISTS: no importa qué columna se seleccione, solo interesa si hay al menos una fila que cumpla la condición.
    BEGIN
        RAISERROR(
            'El IdUsuario %d no pertenece a ningún usuario registrado.',
            16, 1,
            @IdUsuario  -- El parámetro se inserta en el mensaje con %d
        );
        RETURN;
    END

    SELECT
        u.IdUsuario,
        u.NombreUsuario,
        u.Email,
        u.FechaRegistro,

        -- Plan y estado actual: subconsulta con TOP 1 ORDER BY FechaInicio DESC para tomar siempre la suscripción más reciente del usuario. Un JOIN directo con Suscripciones produciría múltiples filas para usuarios con historial de cambios de plan.
        ult.IdPlan                              AS PlanActual, -- ult = última suscripción
        es.DescripcionEstadoSuscripcion         AS EstadoPlan,

        -- Cantidad de proyectos activos del usuario.
        (
            SELECT COUNT(*)
            FROM Proyectos
            WHERE IdUsuario = u.IdUsuario
        )                                       AS CantidadProyectos,

        -- Total de alertas configuradas en todos sus proyectos. El INNERJOIN con Proyectos es necesario para filtrar solo las configuraciones de los proyectos del usuario.
        (
            SELECT COUNT(ac.IdAlertaConfiguracion)
            FROM AlertasConfiguraciones ac
            INNER JOIN Proyectos p ON ac.IdProyecto = p.IdProyecto
            WHERE p.IdUsuario = u.IdUsuario
        )                                       AS TotalAlertasConfiguradas,

        -- Suma de donaciones recibidas en todas sus transmisiones. Solo los eventos de tipo 'tip' tienen ValorDonado > 0; los demás tienen 0.00 por defecto (supuesto explícito del modelo).
        -- SUM sobre todos los eventos incluye los ceros, lo cual es correcto: el total de donaciones incluye todos los eventos de alerta del canal.
        (
            SELECT ISNULL(SUM(ae.ValorDonado), 0.00)
            FROM AlertasEventos ae
            INNER JOIN AlertasConfiguraciones ac ON ae.IdAlertaConfiguracion = ac.IdAlertaConfiguracion
            INNER JOIN Proyectos p               ON ac.IdProyecto = p.IdProyecto
            WHERE p.IdUsuario = u.IdUsuario
        )                                       AS TotalDonacionesUSD,

        -- Cantidad de assets comprados (cada compra es un evento separado, un mismo asset puede comprarse más de una vez según supuesto 4).
        (
            SELECT COUNT(*)
            FROM ComprasAssets
            WHERE IdUsuario = u.IdUsuario
        )                                       AS CantidadAssetsComprados,

        -- Monto total invertido en assets.
        (
            SELECT ISNULL(SUM(Monto), 0.00)
            FROM ComprasAssets
            WHERE IdUsuario = u.IdUsuario
        )                                       AS TotalInvertidoAssetsUSD

    FROM Usuarios u
    -- Subconsulta escalar para obtener la suscripción más reciente.
    -- TOP 1 + ORDER BY FechaInicio DESC garantiza exactamente una fila independientemente del historial de cambios de plan del usuario.
    INNER JOIN (
        SELECT TOP 1 IdPlan, IdEstadoSuscripcion
        FROM Suscripciones
        WHERE IdUsuario = @IdUsuario
        ORDER BY FechaInicio DESC
    ) ult ON 1 = 1  -- JOIN sin condición de clave porque la subconsulta ya filtró por @IdUsuario
    -- JOIN con tabla normalizada: reemplaza la referencia directa a Estado VARCHAR
    INNER JOIN EstadosSuscripcion es ON ult.IdEstadoSuscripcion = es.IdEstadoSuscripcion
    WHERE u.IdUsuario = @IdUsuario;
END;
GO



-- STORED PROCEDURE 3: sp_ReporteDonacionesRango

-- PROPÓSITO:
--   Extrae el detalle de todos los eventos de donación (alertas de tipo 'tip') cuyo monto esté dentro de un rango especificado. Permite al dashboard analizar el comportamiento de las donaciones: quiénes donan, a qué canales, en qué montos.

-- PARÁMETROS:
--   @MontoMinimo DECIMAL(10,2) — DEFAULT 0.00. Monto mínimo de donación.
--   @MontoMaximo DECIMAL(10,2) — DEFAULT 999999.99. Monto máximo de donación.
--   Ambos son opcionales: si no se proveen, devuelve todas las donaciones.

-- POR QUÉ SP Y NO VISTA:
--   Una vista que mostrara todas las donaciones sería útil, pero el dashboard necesita poder explorar rangos específicos: "¿quiénes son los top donadores (más de $50)?" o "¿cuántas donaciones pequeñas (menos de $5) recibimos?". Esos filtros son exactamente el caso de uso de un SP parametrizado.

-- VALIDACIÓN DE PARÁMETROS:
--   Sin validación, un MontoMinimo negativo o un MontoMaximo menor que el mínimo devolverían cero filas sin advertencia al dashboard.

IF OBJECT_ID('sp_ReporteDonacionesRango', 'P') IS NOT NULL
    DROP PROCEDURE sp_ReporteDonacionesRango;
GO

CREATE PROCEDURE sp_ReporteDonacionesRango
    @MontoMinimo DECIMAL(10, 2) = 0.00,        -- Default: desde 0 (incluye todas)
    @MontoMaximo DECIMAL(10, 2) = 999999.99    -- Default: sin límite superior práctico
AS
BEGIN
    SET NOCOUNT ON;

    -- Validación 1: MontoMinimo no puede ser negativo.
    -- ValorDonado tiene CHECK >= 0, por lo que ninguna donación puede ser negativa. Un mínimo negativo sería semánticamente inválido.
    IF @MontoMinimo < 0
    BEGIN
        RAISERROR(
            'MontoMinimo no puede ser negativo. Las donaciones son siempre >= 0.',
            16, 1
        );
        RETURN;
    END

    -- Validación 2: MontoMaximo debe ser mayor o igual al mínimo. Si no lo es, la condición BETWEEN nunca sería verdadera y el SP devolvería cero filas sin advertencia.
    IF @MontoMaximo < @MontoMinimo
    BEGIN
        RAISERROR(
            'Parámetros inválidos: MontoMaximo debe ser mayor o igual a MontoMinimo.',
            16,
            1
        );
        RETURN;
    END

    SELECT
        ae.IdAlertaEvento,
        u.NombreUsuario                         AS Donante,
        proj.Nombre                             AS CanalStreamer,
        ac.Nombre                               AS ConfiguracionAlerta,
        ae.ValorDonado,
        ae.FechaEvento
    FROM AlertasEventos ae
    INNER JOIN AlertasConfiguraciones ac  ON ae.IdAlertaConfiguracion = ac.IdAlertaConfiguracion
    INNER JOIN TiposAlerta ta             ON ac.IdTipoAlerta = ta.IdTipoAlerta
    INNER JOIN Proyectos proj             ON ac.IdProyecto = proj.IdProyecto
    INNER JOIN Usuarios u                 ON ae.IdUsuario = u.IdUsuario
    WHERE
        -- Filtro por tipo: solo eventos de donación monetaria. Se compara contra la descripción en la tabla normalizada, no contra un string hardcodeado en la columna de la tabla de eventos.
        ta.DescripcionTipoAlerta = 'tip'
        -- Filtro por rango de monto: BETWEEN es inclusivo en ambos extremos, coherente con los defaults (MontoMinimo = 0.00 incluye donaciones de $0.00 si las hubiera).
        AND ae.ValorDonado BETWEEN @MontoMinimo AND @MontoMaximo
    -- Orden descendente por monto: el dashboard muestra primero las donaciones más grandes, que son las más relevantes para el análisis de comportamiento.
    ORDER BY ae.ValorDonado DESC, ae.FechaEvento DESC;
END;
GO


-- TESTS RÁPIDOS — descomentar para validar que los SPs funcionan después de correr SQLQuery1.sql, SQLQuery2.sql y SQLQuery3.sql:
-- -- SP 1: compras del último mes, todos los tipos
EXEC sp_BuscarComprasAssets
    @FechaInicio = '2025-01-01', -- ajustar según el rango real que te haya quedado
    @FechaFin    = '2026-12-15';

-- -- SP 1: solo assets de tipo audio
EXEC sp_BuscarComprasAssets
    @FechaInicio = '2025-01-01',
    @FechaFin    = '2026-06-14',
    @TipoAsset   = 'audio';
--
-- -- SP 2: ficha del usuario 1
EXEC sp_FichaRendimientoStreamer @IdUsuario = 13;

-- -- SP 3: todas las donaciones
EXEC sp_ReporteDonacionesRango;

-- -- SP 3: solo donaciones grandes (más de $50)
EXEC sp_ReporteDonacionesRango @MontoMinimo = 50.00;

-- -- SP 3: donaciones pequeñas (entre $1 y $15)
EXEC sp_ReporteDonacionesRango @MontoMinimo = 1.00, @MontoMaximo = 15.00;


PRINT 'Stored Procedures creados (3):';
PRINT '  1. sp_BuscarComprasAssets(@FechaInicio, @FechaFin, @TipoAsset = NULL)';
PRINT '  2. sp_FichaRendimientoStreamer(@IdUsuario)';
PRINT '  3. sp_ReporteDonacionesRango(@MontoMinimo = 0, @MontoMaximo = 999999)';
GO
