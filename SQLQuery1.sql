-- TRABAJO PRÁCTICO FINAL INTEGRADOR - BASES DE DATOS
-- DESCRIPCIÓN: Script para inicializar y crear la base de datos en SQL Server.

-- Usar la base de datos del sistema master para realizar operaciones de administración
USE master;
GO

-- Validar si la base de datos ya existe para eliminarla y asegurar una recreación limpia
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'MagicDB')
BEGIN
    PRINT 'La base de datos MagicDB ya existe. Procediendo a eliminarla...';
    -- Cerrar conexiones activas de forma inmediata para poder eliminarla
    ALTER DATABASE MagicDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MagicDB;
    PRINT 'Base de datos eliminada exitosamente.';
END
GO

-- Crear la base de datos desde cero
CREATE DATABASE MagicDB;
GO

PRINT 'Base de datos MagicDB creada exitosamente.';
GO

-- Posicionar el contexto en la base de datos recién creada
USE MagicDB;
GO
