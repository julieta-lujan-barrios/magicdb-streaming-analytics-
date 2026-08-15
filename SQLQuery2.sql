-- TRABAJO PRÁCTICO FINAL INTEGRADOR - BASES DE DATOS
-- DESCRIPCIÓN: DDL de creación de las 12 tablas con restricciones explícitas.

-- Asegurar que estamos trabajando sobre la base de datos correcta
USE MagicDB;
GO

-- 1. CREACIÓN DE TABLAS (ORDENADAS POR DEPENDENCIAS PARA EVITAR CONFLICTOS DE FK)

-- Tabla 1: Planes
-- Define los planes de suscripción disponibles en la plataforma.
CREATE TABLE Planes (
    IdPlan VARCHAR(50) NOT NULL, -- VARCHAR(50) para permitir códigos alfanuméricos como 'BASIC', 'PREMIUM', etc.
    Nombre VARCHAR(100) NOT NULL,
    PrecioMensual DECIMAL(10, 2) NOT NULL,
    MaxProyectos INT NOT NULL,
    MaxAlertas INT NOT NULL,

    -- Restricciones
    CONSTRAINT PK_Planes PRIMARY KEY (IdPlan),
    CONSTRAINT CK_Planes_PrecioMensual CHECK (PrecioMensual >= 0),
    CONSTRAINT CK_Planes_MaxProyectos CHECK (MaxProyectos >= 1),
    CONSTRAINT CK_Planes_MaxAlertas CHECK (MaxAlertas >= 1)
);
GO --GO para separar los bloques de código y asegurar que cada comando se ejecute correctamente antes de continuar con el siguiente.


-- Tabla 2: Usuarios
-- Almacena los perfiles públicos de los streamers / creadores de contenido.
CREATE TABLE Usuarios (
    IdUsuario INT IDENTITY(1, 1) NOT NULL, -- IDENTITY para autoincrementar el IdUsuario
    Email VARCHAR(255) NOT NULL,
    NombreUsuario VARCHAR(100) NOT NULL,
    FechaRegistro DATETIME2 NOT NULL DEFAULT SYSDATETIME(), --DATETIME2 Tiene mayor precisión que DATETIME, específicamente tiene 7 milésimas de segundo más de precisión 

    -- Restricciones
    CONSTRAINT PK_Usuarios PRIMARY KEY (IdUsuario),
    CONSTRAINT UQ_Usuarios_Email UNIQUE (Email),
    CONSTRAINT UQ_Usuarios_NombreUsuario UNIQUE (NombreUsuario)
);
GO


-- Tabla 3: EstadosSuscripcion
-- Tabla referencial para normalizar los estados posibles de una suscripción.
CREATE TABLE EstadosSuscripcion (
    IdEstadoSuscripcion INT IDENTITY(1, 1) NOT NULL, -- IDENTITY para autoincrementar el IdEstadoSuscripcion, (1, 1) significa que el primer valor será 1 y se incrementará en 1 para cada nuevo registro)
    DescripcionEstadoSuscripcion VARCHAR(50) NOT NULL, -- (active, trialing, past_due, canceled, etc.)

    CONSTRAINT PK_EstadosSuscripcion PRIMARY KEY (IdEstadoSuscripcion), --CONSTRAINT para definir la clave primaria de la tabla EstadosSuscripcion, utilizando el campo IdEstadoSuscripcion como identificador único de cada registro.
    CONSTRAINT UQ_EstadosSuscripcion_Descripcion UNIQUE (DescripcionEstadoSuscripcion)
);
GO


-- Tabla 4: Suscripciones
-- Historial y estado de la suscripción de cada usuario a un plan específico.
CREATE TABLE Suscripciones (
    IdSuscripcion INT IDENTITY(1, 1) NOT NULL,
    IdUsuario INT NOT NULL,
    IdPlan VARCHAR(50) NOT NULL,
    IdEstadoSuscripcion INT NOT NULL,
    FechaInicio DATETIME2 NOT NULL DEFAULT SYSDATETIME(), --SYSDATETIME() para establecer la fecha y hora actual del sistema al momento de la creación del registro, con mayor precisión que GETDATE().
    FechaFin DATETIME2 NULL,

    -- Restricciones
    CONSTRAINT PK_Suscripciones PRIMARY KEY (IdSuscripcion),
    CONSTRAINT FK_Suscripciones_Usuarios FOREIGN KEY (IdUsuario) REFERENCES Usuarios(IdUsuario) ON DELETE CASCADE,
    CONSTRAINT FK_Suscripciones_Planes FOREIGN KEY (IdPlan) REFERENCES Planes(IdPlan) ON DELETE NO ACTION,
    CONSTRAINT FK_Suscripciones_EstadosSuscripcion FOREIGN KEY (IdEstadoSuscripcion) REFERENCES EstadosSuscripcion(IdEstadoSuscripcion) ON DELETE NO ACTION
);
GO


-- Tabla 5: Proyectos
-- Los espacios de trabajo o canales de streaming que configuran los usuarios.
CREATE TABLE Proyectos (
    IdProyecto INT IDENTITY(1, 1) NOT NULL,
    IdUsuario INT NOT NULL,
    Nombre VARCHAR(100) NOT NULL,
    FechaCreacion DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

    -- Restricciones
    CONSTRAINT PK_Proyectos PRIMARY KEY (IdProyecto),
    CONSTRAINT FK_Proyectos_Usuarios FOREIGN KEY (IdUsuario) REFERENCES Usuarios(IdUsuario) ON DELETE CASCADE
);
GO


-- Tabla 6: TiposAlerta
-- Tabla referencial para normalizar los tipos posibles de alerta.
CREATE TABLE TiposAlerta (
    IdTipoAlerta INT IDENTITY(1, 1) NOT NULL,
    DescripcionTipoAlerta VARCHAR(50) NOT NULL, -- (custom, tip, raid, follow, sub, etc.)

    CONSTRAINT PK_TiposAlerta PRIMARY KEY (IdTipoAlerta),
    CONSTRAINT UQ_TiposAlerta_Descripcion UNIQUE (DescripcionTipoAlerta)
);
GO


-- Tabla 7: AlertasConfiguraciones
-- Widgets de alertas configurados en los proyectos de los streamers.
CREATE TABLE AlertasConfiguraciones (
    IdAlertaConfiguracion INT IDENTITY(1, 1) NOT NULL,
    IdProyecto INT NOT NULL,
    IdTipoAlerta INT NOT NULL,
    Nombre VARCHAR(100) NOT NULL,
    Activo BIT NOT NULL DEFAULT 1,
    FechaCreacion DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

    -- Restricciones
    CONSTRAINT PK_AlertasConfiguraciones PRIMARY KEY (IdAlertaConfiguracion),
    CONSTRAINT FK_AlertasConfiguraciones_Proyectos FOREIGN KEY (IdProyecto) REFERENCES Proyectos(IdProyecto) ON DELETE CASCADE,
    CONSTRAINT FK_AlertasConfiguraciones_TiposAlerta FOREIGN KEY (IdTipoAlerta) REFERENCES TiposAlerta(IdTipoAlerta) ON DELETE NO ACTION
);
GO


-- Tabla 8: AlertasEventos (TABLA PRINCIPAL / TRANSACCIONAL 1000+ FILAS)
-- Historial detallado de todas las alertas que se ejecutan en tiempo real.
CREATE TABLE AlertasEventos (
    IdAlertaEvento INT IDENTITY(1, 1) NOT NULL,
    IdAlertaConfiguracion INT NOT NULL,
    IdUsuario INT NOT NULL, -- El usuario que interactúa/desencadena el evento de alerta
    ValorDonado DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    FechaEvento DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

    -- Restricciones
    CONSTRAINT PK_AlertasEventos PRIMARY KEY (IdAlertaEvento),
    CONSTRAINT FK_AlertasEventos_AlertasConfiguraciones FOREIGN KEY (IdAlertaConfiguracion) REFERENCES AlertasConfiguraciones(IdAlertaConfiguracion) ON DELETE CASCADE, -- ON DELETE CASCADE para eliminar los eventos relacionados si se borra la configuración de alerta correspondiente.
    CONSTRAINT FK_AlertasEventos_Usuarios FOREIGN KEY (IdUsuario) REFERENCES Usuarios(IdUsuario) ON DELETE NO ACTION, -- NO ACTION para evitar eliminar eventos históricos si se borra un usuario, manteniendo la integridad histórica de los datos, siendo los eventos históricos aquellos que ya ocurrieron y se registraron en la base de datos, independientemente de si el usuario asociado sigue existiendo o no.
    CONSTRAINT CK_AlertasEventos_ValorDonado CHECK (ValorDonado >= 0)
);
GO


-- Tabla 9: CatalogoJuegos
-- Catálogo de juegos interactivos disponibles en la plataforma.
CREATE TABLE CatalogoJuegos (
    IdJuego INT IDENTITY(1, 1) NOT NULL,
    Titulo VARCHAR(150) NOT NULL,
    Precio DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    TipoJuego VARCHAR(50) NOT NULL,
    Categoria VARCHAR(100) NOT NULL DEFAULT 'General',
    Activo BIT NOT NULL DEFAULT 1,

    -- Restricciones
    CONSTRAINT PK_CatalogoJuegos PRIMARY KEY (IdJuego),
    CONSTRAINT CK_CatalogoJuegos_Precio CHECK (Precio >= 0),
    CONSTRAINT CK_CatalogoJuegos_TipoJuego CHECK (TipoJuego IN ('html', 'download'))
);
GO


-- Tabla 10: JuegosUsuarios
-- Registro de juegos adquiridos o descargados por los streamers y su actividad.
CREATE TABLE JuegosUsuarios (
    IdJuegoUsuario INT IDENTITY(1, 1) NOT NULL,
    IdUsuario INT NOT NULL,
    IdJuego INT NOT NULL,
    FechaAdquisicion DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CantidadPartidas INT NOT NULL DEFAULT 0,

    -- Restricciones
    CONSTRAINT PK_JuegosUsuarios PRIMARY KEY (IdJuegoUsuario),
    CONSTRAINT FK_JuegosUsuarios_Usuarios FOREIGN KEY (IdUsuario) REFERENCES Usuarios(IdUsuario) ON DELETE CASCADE,
    CONSTRAINT FK_JuegosUsuarios_CatalogoJuegos FOREIGN KEY (IdJuego) REFERENCES CatalogoJuegos(IdJuego) ON DELETE CASCADE,
    CONSTRAINT CK_JuegosUsuarios_CantidadPartidas CHECK (CantidadPartidas >= 0)
);
GO


-- Tabla 11: AssetsTienda
-- Multimedia vendida individualmente (efectos de sonido, videos, imágenes, etc.).
CREATE TABLE AssetsTienda (
    IdAsset INT IDENTITY(1, 1) NOT NULL,
    CodigoAsset VARCHAR(100) NOT NULL,
    Nombre VARCHAR(150) NOT NULL,
    TipoAsset VARCHAR(50) NOT NULL,
    Precio DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    Activo BIT NOT NULL DEFAULT 1,

    -- Restricciones
    CONSTRAINT PK_AssetsTienda PRIMARY KEY (IdAsset),
    CONSTRAINT UQ_AssetsTienda_CodigoAsset UNIQUE (CodigoAsset),
    CONSTRAINT CK_AssetsTienda_Precio CHECK (Precio >= 0),
    CONSTRAINT CK_AssetsTienda_TipoAsset CHECK (TipoAsset IN ('image', 'video', 'audio', 'font'))
);
GO


-- Tabla 12: ComprasAssets (TABLA PRINCIPAL / TRANSACCIONAL 1000+ FILAS)
-- Registro de compras individuales de assets de la tienda por parte de los usuarios.
CREATE TABLE ComprasAssets (
    IdCompraAsset INT IDENTITY(1, 1) NOT NULL,
    IdUsuario INT NOT NULL,
    IdAsset INT NOT NULL,
    Monto DECIMAL(10, 2) NOT NULL,
    FechaCompra DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

    -- Restricciones
    CONSTRAINT PK_ComprasAssets PRIMARY KEY (IdCompraAsset),
    CONSTRAINT FK_ComprasAssets_Usuarios FOREIGN KEY (IdUsuario) REFERENCES Usuarios(IdUsuario) ON DELETE CASCADE,
    CONSTRAINT FK_ComprasAssets_AssetsTienda FOREIGN KEY (IdAsset) REFERENCES AssetsTienda(IdAsset) ON DELETE NO ACTION, -- NO ACTION para evitar eliminar compras históricas si se borra un asset, manteniendo la integridad histórica de los datos, siendo las compras históricas aquellas que ya ocurrieron y se registraron en la base de datos, independientemente de si el asset asociado sigue existiendo o no.
    CONSTRAINT CK_ComprasAssets_Monto CHECK (Monto >= 0)
);
GO

PRINT 'Estructura de las 12 tablas y restricciones creada exitosamente.';
GO