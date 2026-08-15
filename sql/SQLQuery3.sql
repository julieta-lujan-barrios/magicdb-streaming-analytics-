-- TRABAJO PRÁCTICO FINAL INTEGRADOR - BASES DE DATOS
-- DESCRIPCIÓN: Inserción de datos sintéticos mediante lógica procedural T-SQL. Garantiza una distribución realista y un volumen de 1000+ registros.

USE MagicDB;
GO

PRINT 'Iniciando la carga de datos sintéticos...';

-- Desactivar el conteo de filas afectadas para mejorar el rendimiento de la inserción masiva, que significa que no se mostrarán mensajes de "X filas afectadas" después de cada operación de inserción, lo cual es útil para mantener la consola limpia 
SET NOCOUNT ON;
GO


-- 1. POBLADO DE TABLAS DE REFERENCIA Y CATÁLOGOS


-- Carga en Tabla: Planes
INSERT INTO Planes (IdPlan, Nombre, PrecioMensual, MaxProyectos, MaxAlertas)
VALUES 
('free', 'Plan Gratuito', 0.00, 1, 5),
('agency', 'Plan Agencia', 0.00, 5, 15),
('pro', 'Plan Profesional', 10.00, 10, 20),
('premium', 'Plan Premium', 16.00, 15, 25);
GO


-- Carga en Tabla: Usuarios
-- Generación semi-aleatoria cruzando listas de nombres y apellidos de personas comunes.
-- Tablas temporales de apoyo
CREATE TABLE #Nombres (Nombre VARCHAR(50)); --Es tabla temporal porque solo se necesita para esta operación de inserción y no es relevante conservarla después. Estas tablas se crean con un prefijo # para indicar que son temporales y se eliminarán automáticamente al finalizar la sesión o pueden ser eliminadas manualmente con DROP TABLE.
CREATE TABLE #Apellidos (Apellido VARCHAR(50));

INSERT INTO #Nombres VALUES 
('Juan'), ('Pedro'), ('Maria'), ('Jose'), ('Carlos'), ('Luis'), ('Ana'), ('Laura'), ('Sofia'), ('Diego'), 
('Javier'), ('Manuel'), ('Alejandro'), ('Elena'), ('Carmen'), ('Lucia'), ('Marta'), ('Patricia'), ('Daniel'), ('Andres'), 
('Gabriela'), ('Valentina'), ('Sonia'), ('Fernando'), ('Ricardo'), ('Hugo'), ('Martin'), ('Paula'), ('Clara'), ('Gabriel');

INSERT INTO #Apellidos VALUES 
('Gonzalez'), ('Rodriguez'), ('Gomez'), ('Fernandez'), ('Lopez'), ('Diaz'), ('Martinez'), ('Perez'), ('Garcia'), ('Sanchez'), 
('Romero'), ('Alvarez'), ('Torres'), ('Ruiz'), ('Ramirez'), ('Flores'), ('Acosta'), ('Benitez'), ('Medina'), ('Herrera'), 
('Suarez'), ('Castro'), ('Gimenez'), ('Rojas'), ('Silva'), ('Mendez'), ('Vargas'), ('Guzman'), ('Paz'), ('Ortega');

-- Insertamos 60 usuarios únicos mezclando nombres y apellidos de forma pseudo-aleatoria
INSERT INTO Usuarios (Email, NombreUsuario, FechaRegistro)
SELECT TOP 60 
    LOWER(n.Nombre + '.' + a.Apellido + '@gmail.com') AS Email,
    n.Nombre + ' ' + a.Apellido AS NombreUsuario,
    DATEADD(DAY, -CAST(RAND(CHECKSUM(NEWID())) * 365 AS INT), SYSDATETIME()) AS FechaRegistro
FROM #Nombres n
CROSS JOIN #Apellidos a
ORDER BY NEWID();

-- Limpiar tablas temporales
DROP TABLE #Nombres;
DROP TABLE #Apellidos;
GO

PRINT 'Tabla Usuarios poblada con 60 registros.';


-- Carga en Tablas Referenciales: EstadosSuscripcion y TiposAlerta
INSERT INTO EstadosSuscripcion (DescripcionEstadoSuscripcion)
VALUES ('trialing'), ('active'), ('past_due'), ('canceled');

INSERT INTO TiposAlerta (DescripcionTipoAlerta)
VALUES ('follow'), ('sub'), ('tip'), ('raid'), ('custom');
GO

PRINT 'Tablas referenciales EstadosSuscripcion y TiposAlerta pobladas.';

PRINT 'Tabla Usuarios poblada con 60 registros.';



-- Carga en Tabla: Suscripciones
-- Distribución mixta de planes y estados para los 60 usuarios
DECLARE @IdUsuarioSuscripcion INT = 1; -- Se usa @ para declarar variables en T-SQL. Esta variable se inicializa en 1 para comenzar a asignar suscripciones desde el primer usuario registrado.
DECLARE @TotalUsuariosSuscripcion INT; -- T-SQL no permite asignar el resultado de una consulta directamente a una variable sin usar SELECT, por eso se declara la variable @TotalUsuariosSuscripcion para almacenar el conteo total de usuarios que se utilizará en el bucle WHILE.
SELECT @TotalUsuariosSuscripcion = COUNT(*) FROM Usuarios;

WHILE @IdUsuarioSuscripcion <= @TotalUsuariosSuscripcion
BEGIN
    DECLARE @PlanesProb INT = CAST(RAND() * 100 AS INT);
    DECLARE @PlanAsignado VARCHAR(50);
    DECLARE @EstadoAsignado VARCHAR(50);
    DECLARE @IdEstadoAsignado INT;
    DECLARE @FechaRegistroUsuario DATETIME2;
    
    SELECT @FechaRegistroUsuario = FechaRegistro FROM Usuarios WHERE IdUsuario = @IdUsuarioSuscripcion;
    
    -- Para simular Upgrades y Downgrades históricos:
    -- 1. Si el IdUsuario es divisible por 5, simulamos un UPGRADE (comenzó gratis y subió a pro)
    IF @IdUsuarioSuscripcion % 5 = 0
    BEGIN
        -- Suscripción anterior (Free - Cancelada)
        INSERT INTO Suscripciones (IdUsuario, IdPlan, IdEstadoSuscripcion, FechaInicio, FechaFin)
        VALUES (@IdUsuarioSuscripcion, 'free', (SELECT IdEstadoSuscripcion FROM EstadosSuscripcion WHERE DescripcionEstadoSuscripcion = 'canceled'), DATEADD(DAY, -120, @FechaRegistroUsuario), DATEADD(DAY, -60, @FechaRegistroUsuario));
        
        -- Suscripción actual (Pro - Activa)
        INSERT INTO Suscripciones (IdUsuario, IdPlan, IdEstadoSuscripcion, FechaInicio, FechaFin)
        VALUES (@IdUsuarioSuscripcion, 'pro', (SELECT IdEstadoSuscripcion FROM EstadosSuscripcion WHERE DescripcionEstadoSuscripcion = 'active'), DATEADD(DAY, -60, @FechaRegistroUsuario), NULL);
    END
    -- 2. Si el IdUsuario es divisible por 7, simulamos un DOWNGRADE (comenzó en premium y bajó a agency)
    ELSE IF @IdUsuarioSuscripcion % 7 = 0
    BEGIN
        -- Suscripción anterior (Premium - Cancelada)
        INSERT INTO Suscripciones (IdUsuario, IdPlan, IdEstadoSuscripcion, FechaInicio, FechaFin)
        VALUES (@IdUsuarioSuscripcion, 'premium', (SELECT IdEstadoSuscripcion FROM EstadosSuscripcion WHERE DescripcionEstadoSuscripcion = 'canceled'), DATEADD(DAY, -150, @FechaRegistroUsuario), DATEADD(DAY, -90, @FechaRegistroUsuario));

        -- Suscripción actual (Agency - Activa)
        INSERT INTO Suscripciones (IdUsuario, IdPlan, IdEstadoSuscripcion, FechaInicio, FechaFin)
        VALUES (@IdUsuarioSuscripcion, 'agency', (SELECT IdEstadoSuscripcion FROM EstadosSuscripcion WHERE DescripcionEstadoSuscripcion = 'active'), DATEADD(DAY, -90, @FechaRegistroUsuario), NULL);
    END
    -- 3. Para el resto de usuarios, asignamos un plan estándar y un único registro
    ELSE
    BEGIN
        -- Distribución de planes: 30% free, 30% agency, 25% pro, 15% premium
        IF @PlanesProb < 30
        BEGIN
            SET @PlanAsignado = 'free';
            SET @EstadoAsignado = 'active';
        END
        ELSE IF @PlanesProb < 60
        BEGIN
            SET @PlanAsignado = 'agency';
            DECLARE @EstProbS INT = CAST(RAND() * 100 AS INT);
            IF @EstProbS < 75 SET @EstadoAsignado = 'active';
            ELSE IF @EstProbS < 85 SET @EstadoAsignado = 'trialing';
            ELSE IF @EstProbS < 95 SET @EstadoAsignado = 'past_due';
            ELSE SET @EstadoAsignado = 'canceled';
        END
        ELSE IF @PlanesProb < 85
        BEGIN
            SET @PlanAsignado = 'pro';
            DECLARE @EstProbP INT = CAST(RAND() * 100 AS INT);
            IF @EstProbP < 85 SET @EstadoAsignado = 'active';
            ELSE IF @EstProbP < 90 SET @EstadoAsignado = 'trialing';
            ELSE IF @EstProbP < 97 SET @EstadoAsignado = 'past_due';
            ELSE SET @EstadoAsignado = 'canceled';
        END
        ELSE
        BEGIN
            SET @PlanAsignado = 'premium';
            DECLARE @EstProbPrem INT = CAST(RAND() * 100 AS INT);
            IF @EstProbPrem < 85 SET @EstadoAsignado = 'active';
            ELSE IF @EstProbPrem < 90 SET @EstadoAsignado = 'trialing';
            ELSE IF @EstProbPrem < 97 SET @EstadoAsignado = 'past_due';
            ELSE SET @EstadoAsignado = 'canceled';
        END

        -- Fecha fin si está cancelado (fecha aleatoria posterior al registro)
        DECLARE @FechaFinAsignada DATETIME2 = NULL;
        IF @EstadoAsignado = 'canceled'
        BEGIN
            SET @FechaFinAsignada = DATEADD(DAY, CAST(RAND() * 30 AS INT), @FechaRegistroUsuario);
        END

        INSERT INTO Suscripciones (IdUsuario, IdPlan, IdEstadoSuscripcion, FechaInicio, FechaFin)
        VALUES (@IdUsuarioSuscripcion, @PlanAsignado, (SELECT IdEstadoSuscripcion FROM EstadosSuscripcion WHERE DescripcionEstadoSuscripcion = @EstadoAsignado), @FechaRegistroUsuario, @FechaFinAsignada);
    END

    SET @IdUsuarioSuscripcion = @IdUsuarioSuscripcion + 1;
END;
GO

PRINT 'Tabla Suscripciones poblada con 60 registros.';


-- Carga en Tabla: Proyectos
-- Cada usuario tiene entre 1 y 4 proyectos dependiendo de las restricciones del plan
DECLARE @IdUsuarioProyecto INT = 1;
DECLARE @TotalUsuariosProyecto INT;
SELECT @TotalUsuariosProyecto = COUNT(*) FROM Usuarios;

WHILE @IdUsuarioProyecto <= @TotalUsuariosProyecto
BEGIN
    DECLARE @PlanDelUsuario VARCHAR(50);
    DECLARE @FechaReg DATETIME2;
    
    SELECT TOP 1  -- Se hace TOP 1 por si el usuario tiene múltiples suscripciones históricas, se toma la más reciente para determinar su plan actual.
        @PlanDelUsuario = IdPlan
    FROM Suscripciones
    WHERE IdUsuario = @IdUsuarioProyecto
    ORDER BY FechaInicio DESC;

    SELECT @FechaReg = FechaRegistro FROM Usuarios WHERE IdUsuario = @IdUsuarioProyecto;
    
    -- Cantidad de proyectos según el plan
    DECLARE @CantidadProyectos INT = 1;
    IF @PlanDelUsuario = 'agency'
    BEGIN
        -- 70% tiene 1 proyecto, 30% tiene 2
        IF RAND() > 0.7 SET @CantidadProyectos = 2;
    END
    ELSE IF @PlanDelUsuario = 'pro'
    BEGIN
        -- Distribución: 50% tiene 1, 30% tiene 2, 20% tiene 3
        DECLARE @ProProb INT = CAST(RAND() * 100 AS INT);
        IF @ProProb < 50 SET @CantidadProyectos = 1;
        ELSE IF @ProProb < 80 SET @CantidadProyectos = 2;
        ELSE SET @CantidadProyectos = 3;
    END
    ELSE IF @PlanDelUsuario = 'premium'
    BEGIN
        -- Distribución: 30% tiene 1, 40% tiene 2, 20% tiene 3, 10% tiene 4
        DECLARE @PremProb INT = CAST(RAND() * 100 AS INT);
        IF @PremProb < 30 SET @CantidadProyectos = 1;
        ELSE IF @PremProb < 70 SET @CantidadProyectos = 2;
        ELSE IF @PremProb < 90 SET @CantidadProyectos = 3;
        ELSE SET @CantidadProyectos = 4;
    END

    DECLARE @PCount INT = 1;
    WHILE @PCount <= @CantidadProyectos
    BEGIN
        INSERT INTO Proyectos (IdUsuario, Nombre, FechaCreacion)
        VALUES (
            @IdUsuarioProyecto, 
            'Proyecto ' + CASE @PCount WHEN 1 THEN 'Principal' WHEN 2 THEN 'Secundario' ELSE 'Pruebas' END,
            DATEADD(MINUTE, CAST(RAND() * 1000 AS INT), @FechaReg)
        );
        SET @PCount = @PCount + 1;
    END

    SET @IdUsuarioProyecto = @IdUsuarioProyecto + 1;
END;
GO

PRINT 'Tabla Proyectos poblada exitosamente.';


-- Carga en Tabla: AlertasConfiguraciones
-- Crea de 2 a 4 configuraciones de alerta para cada proyecto existente.
DECLARE @IdProyectoConfig INT = 1;
DECLARE @TotalProyectosConfig INT;
SELECT @TotalProyectosConfig = COUNT(*) FROM Proyectos;

WHILE @IdProyectoConfig <= @TotalProyectosConfig
BEGIN
    DECLARE @FechaP DATETIME2;
    SELECT @FechaP = FechaCreacion FROM Proyectos WHERE IdProyecto = @IdProyectoConfig;
    
    -- Insertamos de forma fija alertas principales
    INSERT INTO AlertasConfiguraciones (IdProyecto, IdTipoAlerta, Nombre, Activo, FechaCreacion)
    VALUES 
    (@IdProyectoConfig, (SELECT IdTipoAlerta FROM TiposAlerta WHERE DescripcionTipoAlerta = 'follow'), 'Alerta Nuevo Seguidor', 1, @FechaP),
    (@IdProyectoConfig, (SELECT IdTipoAlerta FROM TiposAlerta WHERE DescripcionTipoAlerta = 'sub'), 'Alerta Nuevo Suscriptor', 1, DATEADD(MINUTE, 5, @FechaP));
    
    -- Probabilidad de alertas adicionales (tips o raids)
    IF RAND() > 0.3 -- 70% de probabilidad de que se agregue una alerta de tip/donación
    BEGIN
        INSERT INTO AlertasConfiguraciones (IdProyecto, IdTipoAlerta, Nombre, Activo, FechaCreacion)
        VALUES (@IdProyectoConfig, (SELECT IdTipoAlerta FROM TiposAlerta WHERE DescripcionTipoAlerta = 'tip'), 'Alerta Donacion Bits/Dinero', 1, DATEADD(MINUTE, 10, @FechaP));
    END
    
    IF RAND() > 0.6 -- 40% de probabilidad de que se agregue una alerta de raid
    BEGIN
        INSERT INTO AlertasConfiguraciones (IdProyecto, IdTipoAlerta, Nombre, Activo, FechaCreacion)
        VALUES (@IdProyectoConfig, (SELECT IdTipoAlerta FROM TiposAlerta WHERE DescripcionTipoAlerta = 'raid'), 'Alerta Raid Entrante', 1, DATEADD(MINUTE, 15, @FechaP)); -- Raid suele ser una alerta más avanzada, por eso la programamos para que se cree después de las otras, raid significa que otro streamer redirige a sus seguidores al canal, lo cual es un evento importante que suele tener su propia alerta personalizada.
    END

    SET @IdProyectoConfig = @IdProyectoConfig + 1;
END;
GO

PRINT 'Tabla AlertasConfiguraciones poblada exitosamente.';


-- Carga en Tabla: CatalogoJuegos
-- Catálogo estático de juegos interactivos de la plataforma
INSERT INTO CatalogoJuegos (Titulo, Precio, TipoJuego, Categoria, Activo)
VALUES
('Survival Chat Arena', 0.00, 'html', 'Supervivencia', 1),
('Zombie Apocalypse Twitch Edition', 14.99, 'download', 'Accion', 1),
('TNT Box Blast', 4.99, 'html', 'Arcade', 1),
('WordGuess Streamer Edition', 0.00, 'html', 'Trivia', 1),
('JumpUp Roblox Run', 9.99, 'download', 'Plataformas', 1),
('Speed Runners Live', 19.99, 'download', 'Carreras', 1),
('Chess Battles on Chat', 0.00, 'html', 'Estrategia', 1),
('Streamer RPG Interactive', 29.99, 'download', 'Rol', 1),
('Trivia Twitch Master', 7.99, 'html', 'Trivia', 1),
('Pixel Pixel Invasion', 2.49, 'html', 'Retro', 0); -- Desactivado para dar realismo, quiere decir que el juego existe pero no está disponible para compra, puede ser por mantenimiento, problemas técnicos o porque el desarrollador lo retiró temporalmente de la tienda.
GO

PRINT 'Tabla CatalogoJuegos poblada.';


-- Carga en Tabla: JuegosUsuarios
-- Registros de descargas/adquisiciones y partidas para los streamers
DECLARE @IdUsuarioJuego INT = 1;
DECLARE @TotalUsuariosJuego INT;
SELECT @TotalUsuariosJuego = COUNT(*) FROM Usuarios;

WHILE @IdUsuarioJuego <= @TotalUsuariosJuego
BEGIN
    -- Los streamers tienen entre 0 y 4 juegos
    DECLARE @CantJuegosAdquiridos INT = CAST(RAND() * 5 AS INT);
    
    IF @CantJuegosAdquiridos > 0
    BEGIN
        -- Insertamos juegos aleatorios únicos para el usuario
        INSERT INTO JuegosUsuarios (IdUsuario, IdJuego, FechaAdquisicion, CantidadPartidas)
        SELECT TOP (@CantJuegosAdquiridos)
            @IdUsuarioJuego,
            IdJuego,
            DATEADD(DAY, -CAST(RAND(CHECKSUM(NEWID())) * 60 AS INT), SYSDATETIME()),
            CAST(RAND(CHECKSUM(NEWID())) * 120 AS INT) -- Cantidad de partidas variada
        FROM CatalogoJuegos
        WHERE Activo = 1
        ORDER BY NEWID();
    END

    SET @IdUsuarioJuego = @IdUsuarioJuego + 1;
END;
GO

PRINT 'Tabla JuegosUsuarios poblada exitosamente.';


-- Carga en Tabla: AssetsTienda
-- Catálogo estático de recursos multimedia en la tienda
INSERT INTO AssetsTienda (CodigoAsset, Nombre, TipoAsset, Precio, Activo)
VALUES
('SND-AIRHORN-01', 'Sonido de Airhorn Retro', 'audio', 0.99, 1),
('SND-SADVIOLIN-02', 'Violin Melancolico Alerta', 'audio', 1.49, 1),
('SND-ANIMEWOW-03', 'Anime Wow Sound Effect', 'audio', 0.99, 1),
('VID-SCREAMER-04', 'Overlay Video Screamer Asustador', 'video', 4.99, 1),
('VID-FIREWORKS-05', 'Efecto de Fuegos Artificiales 4K', 'video', 3.99, 1),
('IMG-GGWP-06', 'Imagen Animated GG WP Badge', 'image', 1.99, 1),
('IMG-CROWN-07', 'Corona Dorada Streamer King', 'image', 2.99, 1),
('FNT-CYBERPUNK-08', 'Fuente Tipografica Cyber Neon', 'font', 0.99, 1),
('FNT-RETROGAME-09', 'Fuente Pixel Art 8-bits', 'font', 0.99, 1),
('VID-MATRIX-10', 'Fondo Matrix de Lluvia de Codigo', 'video', 5.99, 1),
('SND-COINS-11', 'Sonido Retro Monedas Mario', 'audio', 1.20, 1),
('IMG-HEART-12', 'Imagen Corazon Pixelado Glitch', 'image', 1.50, 1),
('VID-MEMEDANCE-13', 'Meme Dance Overlay Transparente', 'video', 7.99, 1),
('FNT-GOTHIC-14', 'Fuente Tipografica Gotica Moderna', 'font', 0.00, 1); -- Gratuita, pero se incluye en el catálogo para dar variedad, puede ser un recurso promocional o parte de una campaña de marketing para atraer a los streamers a probar la tienda.
GO

PRINT 'Tabla AssetsTienda poblada.';



-- 2. CARGA DE TABLAS PRINCIPALES (ALTA CARDINALIDAD: 1000+ FILAS POR TABLA)

-- Carga en Tabla: ComprasAssets (TABLA PRINCIPAL 1) - MÍNIMO 1000 REGISTROS
-- Simulación de transacciones de compra con distribución realista en los últimos 6 meses.
PRINT 'Generando 1050 registros de ComprasAssets...';

-- Crear una tabla temporal de usuarios compradores autorizados (40% del total -> 24 usuarios de 60)
-- Esto garantiza una tasa de conversión del 40% en las compras, lo cual es realista para una tienda de assets dentro de una plataforma de streaming, donde no todos los usuarios compran pero sí una proporción significativa.
CREATE TABLE #CompradoresPermitidos (IdUsuario INT);
INSERT INTO #CompradoresPermitidos
SELECT TOP 24 IdUsuario FROM Usuarios ORDER BY NEWID();

DECLARE @ContadorCompras INT = 1;
DECLARE @TotalAssets INT;
SELECT @TotalAssets = COUNT(*) FROM AssetsTienda;

WHILE @ContadorCompras <= 1050
BEGIN
    DECLARE @IdUsuarioCompra INT;
    DECLARE @IdAssetCompra INT;
    DECLARE @PrecioAsset DECIMAL(10,2);
    
    -- Seleccionar un usuario únicamente del subconjunto de compradores autorizados
    SELECT TOP 1 @IdUsuarioCompra = IdUsuario
    FROM #CompradoresPermitidos
    ORDER BY NEWID(); -- NEWID() se utiliza para obtener un registro aleatorio de la tabla temporal, lo que garantiza que cada compra se asigne a un usuario diferente dentro del grupo de compradores permitidos.
    
    -- Seleccionar asset aleatorio de la tienda
    SELECT TOP 1 @IdAssetCompra = IdAsset, @PrecioAsset = Precio
    FROM AssetsTienda
    WHERE Activo = 1
    ORDER BY NEWID();
    
    -- Obtener la fecha de registro del usuario seleccionado
    DECLARE @FechaRegistroUsuarioCompra DATETIME2;
    SELECT @FechaRegistroUsuarioCompra = FechaRegistro FROM Usuarios WHERE IdUsuario = @IdUsuarioCompra;

    -- Calcular los segundos transcurridos desde que el usuario se registró hasta hoy
    DECLARE @SegundosTotalesActivo INT = DATEDIFF(SECOND, @FechaRegistroUsuarioCompra, SYSDATETIME());
    -- Generar una fecha de compra aleatoria que esté estrictamente DESPUÉS de su registro
    DECLARE @SegundosAleatoriosCompra INT = CAST(RAND() * @SegundosTotalesActivo AS INT);
    DECLARE @FechaCompraAleatoria DATETIME2 = DATEADD(SECOND, @SegundosAleatoriosCompra, @FechaRegistroUsuarioCompra);
    
    INSERT INTO ComprasAssets (IdUsuario, IdAsset, Monto, FechaCompra)
    VALUES (@IdUsuarioCompra, @IdAssetCompra, @PrecioAsset, @FechaCompraAleatoria);
    
    SET @ContadorCompras = @ContadorCompras + 1;
END;

-- Limpiar tabla temporal
DROP TABLE #CompradoresPermitidos;
GO

PRINT 'Tabla ComprasAssets cargada con exitosamente.';
SELECT COUNT(*) AS [filas_compras_assets] FROM ComprasAssets ;


-- Carga en Tabla: AlertasEventos (TABLA PRINCIPAL 2) - MÍNIMO 1000 REGISTROS
-- Simulación de eventos de alertas en vivo con distribución realista (Tips, subs, follows, etc.)
PRINT 'Generando 1500 registros de AlertasEventos...';

DECLARE @ContadorEventos INT = 1;
DECLARE @TotalAlertasConfig INT;
SELECT @TotalAlertasConfig = COUNT(*) FROM AlertasConfiguraciones;

DECLARE @TotalUsuariosEventos INT;
SELECT @TotalUsuariosEventos = COUNT(*) FROM Usuarios;

WHILE @ContadorEventos <= 1500
BEGIN
    DECLARE @IdAlertaConfigAleatorio INT;
    DECLARE @IdUsuarioEvento INT;
    DECLARE @TipoAlerta VARCHAR(50);
    DECLARE @ValorDonadoAleatorio DECIMAL(10,2) = 0.00;
    
    -- Seleccionar configuración de alerta aleatoria y obtener la fecha de creación de su proyecto asociado
    DECLARE @FechaCreacionProyecto DATETIME2;
    SELECT TOP 1 
        @IdAlertaConfigAleatorio = ac.IdAlertaConfiguracion, 
        @TipoAlerta = ta.DescripcionTipoAlerta,
        @FechaCreacionProyecto = p.FechaCreacion
    FROM AlertasConfiguraciones ac
    INNER JOIN TiposAlerta ta ON ac.IdTipoAlerta = ta.IdTipoAlerta
    INNER JOIN Proyectos p ON ac.IdProyecto = p.IdProyecto
    ORDER BY NEWID();
    
    -- Seleccionar usuario aleatorio (el espectador que interactúa o dona)
    SELECT TOP 1 @IdUsuarioEvento = IdUsuario
    FROM Usuarios
    ORDER BY NEWID();
    
    -- Si la alerta es de tipo 'tip' (donación en dinero), se genera un monto aleatorio realista.
    -- Para dar realismo, aplicamos una regla de distribución:
    -- 75% donaciones pequeñas ($1 a $15)
    -- 20% donaciones medianas ($15 a $50)
    -- 5% donaciones grandes ($50 a $300)
    IF @TipoAlerta = 'tip'
    BEGIN
        DECLARE @ProbabilidadDonacion DECIMAL(10,2) = RAND() * 100.0;
        IF @ProbabilidadDonacion < 75.0
            SET @ValorDonadoAleatorio = 1.00 + (RAND() * 14.00);
        ELSE IF @ProbabilidadDonacion < 95.0
            SET @ValorDonadoAleatorio = 15.00 + (RAND() * 35.00);
        ELSE
            SET @ValorDonadoAleatorio = 50.00 + (RAND() * 250.00);
    END
    
    -- Calcular los segundos transcurridos desde que se creó el proyecto hasta hoy
    DECLARE @SegundosTotalesProyecto INT = DATEDIFF(SECOND, @FechaCreacionProyecto, SYSDATETIME());
    -- Generar una fecha de evento aleatoria que sea estrictamente posterior a la creación del proyecto
    DECLARE @SegundosAleatoriosEvento INT = CAST(RAND() * @SegundosTotalesProyecto AS INT);
    DECLARE @FechaEventoAleatoria DATETIME2 = DATEADD(SECOND, @SegundosAleatoriosEvento, @FechaCreacionProyecto);
    
    -- Ajustar la distribución horaria para simular transmisiones (mayor actividad por la tarde-noche: 18:00 a 02:00)
    -- Si la hora es de madrugada/mañana (03:00 a 12:00), con un 70% de probabilidad la movemos a la tarde-noche
    DECLARE @HoraGenerada INT = DATEPART(HOUR, @FechaEventoAleatoria);
    IF (@HoraGenerada >= 3 AND @HoraGenerada <= 12 AND RAND() > 0.3)
    BEGIN
        -- Sumarle 10 horas para mover el evento a una hora pico de transmisiones
        SET @FechaEventoAleatoria = DATEADD(HOUR, 10, @FechaEventoAleatoria);
    END

    INSERT INTO AlertasEventos (IdAlertaConfiguracion, IdUsuario, ValorDonado, FechaEvento)
    VALUES (@IdAlertaConfigAleatorio, @IdUsuarioEvento, @ValorDonadoAleatorio, @FechaEventoAleatoria);
    
    SET @ContadorEventos = @ContadorEventos + 1;
END;
GO

PRINT 'Tabla AlertasEventos cargada exitosamente.';
SELECT COUNT(*) AS [filas_alertas_eventos] FROM AlertasEventos ;



-- 3. FINALIZAR CARGA
SET NOCOUNT OFF;
GO

PRINT 'Carga de datos sintéticos completada con éxito para todas las tablas.';
GO
