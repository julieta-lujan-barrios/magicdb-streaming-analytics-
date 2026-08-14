-- TRABAJO PRÁCTICO FINAL INTEGRADOR - BASES DE DATOS
-- DESCRIPCIÓN: Consultas recomendadas en el Entregable 2 para verificar que la creación de tablas (SQLQuery2.sql) y la carga de datos (SQLQuery3.sql) se ejecutaron correctamente.
-- No forman parte del modelo ni de la capa de acceso: son validaciones manuales post-carga.

USE MagicDB;
GO

-- 1. Conteo general por tabla
-- Esperado: AlertasEventos >= 1500, ComprasAssets >= 1050
SELECT 'Usuarios' AS Tabla, COUNT(*) AS Total FROM Usuarios
UNION ALL SELECT 'Suscripciones', COUNT(*) FROM Suscripciones -- UNION ALL para mostrar todas las tablas en un solo resultado
UNION ALL SELECT 'Proyectos', COUNT(*) FROM Proyectos -- Muestra 82 porque se asignan 82 proyectos a los 60 usuarios (algunos usuarios tienen más de un proyecto)
UNION ALL SELECT 'AlertasConfiguraciones', COUNT(*) FROM AlertasConfiguraciones
UNION ALL SELECT 'AlertasEventos', COUNT(*) FROM AlertasEventos
UNION ALL SELECT 'ComprasAssets', COUNT(*) FROM ComprasAssets;
GO


-- 2. Verificación de tablas principales (mínimo 1000 filas exigido)
-- Esperado: 1050
SELECT COUNT(*) AS TotalCompras FROM ComprasAssets;
-- Esperado: 1500
SELECT COUNT(*) AS TotalEventos FROM AlertasEventos;
GO


-- 3. Verificación de compradores únicos
-- Esperado: 24 compradores únicos (40% de 60 usuarios)
SELECT COUNT(DISTINCT IdUsuario) AS CompradoresUnicos FROM ComprasAssets;
GO

-- 4. Verificación de proyectos por usuario
-- Esperado: al menos 1 proyecto por usuario, algunos usuarios con más de 1 proyecto
SELECT IdUsuario, COUNT(*) AS TotalProyectos
FROM Proyectos
GROUP BY IdUsuario
ORDER BY TotalProyectos DESC; -- Ordenado para identificar usuarios con más proyectos
GO

-- 5. Verificación de distribución de estados de suscripción
-- Esperado: presencia de active, trialing, past_due y canceled
-- Nota: requiere JOIN con EstadosSuscripcion por el diseño normalizado
SELECT es.DescripcionEstadoSuscripcion, COUNT(*) AS Total
FROM Suscripciones s
INNER JOIN EstadosSuscripcion es ON s.IdEstadoSuscripcion = es.IdEstadoSuscripcion
GROUP BY es.DescripcionEstadoSuscripcion;
GO