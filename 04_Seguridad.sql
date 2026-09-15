-- =====================================================================
-- PROYECTO BASE DE DATOS AVANZADA - E-COMMERCE
-- Archivo 04: Seguridad y Permisos
--
-- Requisito previo: haber ejecutado 01_Esquema_y_Datos.sql
--   (los GRANT fallan con error 1146 si las tablas todavia no existen)
-- =====================================================================

USE ecommerce_db;


-- =====================================================================
-- LIMPIEZA PREVIA
-- Permite volver a ejecutar el archivo sin errores de "ya existe".
-- =====================================================================

DROP USER IF EXISTS 'admin_user'@'%';
DROP USER IF EXISTS 'marketing_user'@'%';
DROP USER IF EXISTS 'inventory_user'@'%';
DROP USER IF EXISTS 'support_user'@'%';
DROP USER IF EXISTS 'analyst_user'@'%';

DROP ROLE IF EXISTS 'administrador_sistema';
DROP ROLE IF EXISTS 'gerente_marketing';
DROP ROLE IF EXISTS 'analista_datos';
DROP ROLE IF EXISTS 'empleado_inventario';
DROP ROLE IF EXISTS 'atencion_cliente';
DROP ROLE IF EXISTS 'auditor_financiero';
DROP ROLE IF EXISTS 'visitante';


-- =====================================================================
-- SECCION A: CREACION DE ROLES (requerimientos 1 al 6)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. administrador_sistema: todos los privilegios sobre la base.
--    Se limita a ecommerce_db.* y no se da GRANT a nivel global (*.*)
--    para que no pueda tocar las bases del sistema (mysql, sys).
-- ---------------------------------------------------------------------
CREATE ROLE 'administrador_sistema';
GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'administrador_sistema';


-- ---------------------------------------------------------------------
-- 2. gerente_marketing: solo lectura sobre ventas y clientes.
--    Se agrega detalle_ventas porque sin ella no se puede analizar
--    QUE se vendio, solo cuanto.
--    EXECUTE permite correr los procedimientos de reporte (req. 12).
-- ---------------------------------------------------------------------
CREATE ROLE 'gerente_marketing';
GRANT SELECT  ON ecommerce_db.ventas         TO 'gerente_marketing';
GRANT SELECT  ON ecommerce_db.clientes       TO 'gerente_marketing';
GRANT SELECT  ON ecommerce_db.detalle_ventas TO 'gerente_marketing';
GRANT SELECT  ON ecommerce_db.productos      TO 'gerente_marketing';
-- Requerimiento 12: poder ejecutar los procedimientos de reporte.
-- El permiso se da a nivel de base de datos y no procedimiento por
-- procedimiento, porque un GRANT sobre una rutina concreta falla si esa
-- rutina todavia no existe, y los procedimientos se crean en el
-- archivo 07, despues de este.
GRANT EXECUTE ON ecommerce_db.* TO 'gerente_marketing';


-- ---------------------------------------------------------------------
-- 3. analista_datos: solo lectura sobre TODAS las tablas de negocio,
--    EXCEPTO las de auditoria y log.
--    Por eso los permisos se dan tabla por tabla y no con
--    GRANT SELECT ON ecommerce_db.*, que incluiria las de auditoria.
-- ---------------------------------------------------------------------
CREATE ROLE 'analista_datos';
GRANT SELECT ON ecommerce_db.categorias     TO 'analista_datos';
GRANT SELECT ON ecommerce_db.proveedores    TO 'analista_datos';
GRANT SELECT ON ecommerce_db.productos      TO 'analista_datos';
GRANT SELECT ON ecommerce_db.clientes       TO 'analista_datos';
GRANT SELECT ON ecommerce_db.ventas         TO 'analista_datos';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'analista_datos';
GRANT SELECT ON ecommerce_db.promociones    TO 'analista_datos';
-- Tablas deliberadamente EXCLUIDAS de este rol:
--   log_cambios_precio, log_clientes,
--   log_ejecucion_eventos, log_ejecucion_eventos_historico


-- ---------------------------------------------------------------------
-- 4. empleado_inventario: solo puede modificar productos, y dentro de
--    productos solo las columnas stock y ubicacion.
--    El permiso se otorga a nivel de COLUMNA. Esto ya deja por fuera
--    precio, costo y cualquier otro campo sensible (ver req. 14).
-- ---------------------------------------------------------------------
CREATE ROLE 'empleado_inventario';
GRANT SELECT                     ON ecommerce_db.productos TO 'empleado_inventario';
GRANT UPDATE (stock, ubicacion)  ON ecommerce_db.productos TO 'empleado_inventario';
GRANT SELECT                     ON ecommerce_db.categorias  TO 'empleado_inventario';
GRANT SELECT                     ON ecommerce_db.proveedores TO 'empleado_inventario';


-- ---------------------------------------------------------------------
-- 5. atencion_cliente: puede consultar clientes y ventas para atender
--    reclamos, pero NO puede modificar precios.
--    Sobre productos se otorga SELECT restringido a columnas no
--    sensibles: el agente ve nombre y stock, nunca precio ni costo.
-- ---------------------------------------------------------------------
CREATE ROLE 'atencion_cliente';
GRANT SELECT ON ecommerce_db.clientes       TO 'atencion_cliente';
GRANT SELECT ON ecommerce_db.ventas         TO 'atencion_cliente';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'atencion_cliente';
GRANT SELECT (id_producto, nombre, descripcion, stock, activo)
             ON ecommerce_db.productos      TO 'atencion_cliente';
-- Al no otorgar UPDATE sobre productos, el rol no puede modificar
-- precios aunque quisiera. La restriccion es estructural, no una regla
-- de aplicacion que se pueda saltar.


-- ---------------------------------------------------------------------
-- 6. auditor_financiero: solo lectura sobre ventas, productos y el log
--    de cambios de precio. Es el UNICO rol de negocio con acceso a la
--    tabla de auditoria, que es justamente lo que lo hace auditor.
-- ---------------------------------------------------------------------
CREATE ROLE 'auditor_financiero';
GRANT SELECT ON ecommerce_db.ventas             TO 'auditor_financiero';
GRANT SELECT ON ecommerce_db.detalle_ventas     TO 'auditor_financiero';
GRANT SELECT ON ecommerce_db.productos          TO 'auditor_financiero';
GRANT SELECT ON ecommerce_db.clientes           TO 'auditor_financiero';
GRANT SELECT ON ecommerce_db.log_cambios_precio TO 'auditor_financiero';


-- =====================================================================
-- SECCION B: CREACION DE USUARIOS (requerimientos 7 al 10)
--
-- Las contraseñas cumplen la politica por defecto de MySQL 8
-- (componente validate_password, nivel MEDIUM): minimo 8 caracteres,
-- mayuscula, minuscula, digito y caracter especial.
-- En un entorno real estas credenciales NO irian en el repositorio.
-- =====================================================================

-- 7. admin_user -> administrador_sistema
CREATE USER 'admin_user'@'%'     IDENTIFIED BY 'Adm1n#Ecom2026';
GRANT 'administrador_sistema' TO 'admin_user'@'%';
SET DEFAULT ROLE 'administrador_sistema' TO 'admin_user'@'%';

-- 8. marketing_user -> gerente_marketing
CREATE USER 'marketing_user'@'%' IDENTIFIED BY 'Mkt1ng#Ecom2026';
GRANT 'gerente_marketing' TO 'marketing_user'@'%';
SET DEFAULT ROLE 'gerente_marketing' TO 'marketing_user'@'%';

-- 9. inventory_user -> empleado_inventario
CREATE USER 'inventory_user'@'%' IDENTIFIED BY 'Inv3nt#Ecom2026';
GRANT 'empleado_inventario' TO 'inventory_user'@'%';
SET DEFAULT ROLE 'empleado_inventario' TO 'inventory_user'@'%';

-- 10. support_user -> atencion_cliente
CREATE USER 'support_user'@'%'   IDENTIFIED BY 'Supp0rt#Ecom2026';
GRANT 'atencion_cliente' TO 'support_user'@'%';
SET DEFAULT ROLE 'atencion_cliente' TO 'support_user'@'%';

FLUSH PRIVILEGES;


-- =====================================================================
-- SECCION C: REQUERIMIENTOS ADICIONALES IMPLEMENTADOS
-- =====================================================================

-- ---------------------------------------------------------------------
-- 11. Impedir DELETE y TRUNCATE al rol analista_datos.
--     Se cumple por construccion: al rol solo se le otorgo SELECT.
--     En MySQL no se puede "prohibir" un privilegio que nunca se
--     concedio; la forma correcta es no concederlo. La consulta de
--     verificacion al final de este archivo lo demuestra.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 13. Vista v_info_clientes_basica: expone lo minimo necesario para
--     atencion al cliente y oculta la contraseña, la fecha de
--     nacimiento y el gasto historico. El email se enmascara dejando
--     visibles solo los dos primeros caracteres y el dominio.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT
    c.id_cliente,
    c.nombre,
    c.apellido,
    CONCAT(
        LEFT(c.email, 2),
        '****',
        SUBSTRING(c.email, LOCATE('@', c.email))
    )                                   AS email_enmascarado,
    c.direccion_envio,
    c.fecha_registro,
    c.activo
FROM clientes c;

GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'atencion_cliente';

-- ---------------------------------------------------------------------
-- 14. Revocar UPDATE sobre productos.precio al rol empleado_inventario.
--     Ya esta garantizado por el GRANT de la seccion A: el permiso se
--     otorgo solo sobre las columnas (stock, ubicacion). MySQL no
--     acepta REVOKE de un privilegio que no fue concedido (error 1147),
--     por eso la restriccion se implementa al momento de otorgar.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 17. Rol visitante: solo puede ver el catalogo de productos activos.
--     Se apoya en una vista para no exponer el costo de compra.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_catalogo_publico AS
SELECT
    p.id_producto,
    p.nombre,
    p.descripcion,
    p.precio,
    c.nombre AS categoria,
    (p.stock > 0) AS disponible
FROM productos p
LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
WHERE p.activo = TRUE;

CREATE ROLE 'visitante';
GRANT SELECT ON ecommerce_db.v_catalogo_publico TO 'visitante';

-- ---------------------------------------------------------------------
-- 18. Limitar el consumo de recursos del rol analista_datos.
--     Los limites en MySQL se aplican a la CUENTA, no al rol, asi que
--     se crea el usuario del analista y se le imponen los topes.
-- 15. Politica de contraseñas: caducidad cada 90 dias y bloqueo
--     temporal tras 3 intentos fallidos de inicio de sesion.
-- ---------------------------------------------------------------------
CREATE USER 'analyst_user'@'%' IDENTIFIED BY 'An4lyst#Ecom2026'
    WITH MAX_QUERIES_PER_HOUR 1000
         MAX_CONNECTIONS_PER_HOUR 100
         MAX_USER_CONNECTIONS 5;
GRANT 'analista_datos' TO 'analyst_user'@'%';
SET DEFAULT ROLE 'analista_datos' TO 'analyst_user'@'%';

ALTER USER 'admin_user'@'%'     PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1;
ALTER USER 'marketing_user'@'%' PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1;
ALTER USER 'inventory_user'@'%' PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1;
ALTER USER 'support_user'@'%'   PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1;
ALTER USER 'analyst_user'@'%'   PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1;

FLUSH PRIVILEGES;


-- =====================================================================
-- VERIFICACION
-- =====================================================================

-- Roles y usuarios creados
SELECT user AS cuenta,
       host,
       IF(authentication_string = '', 'ROL', 'USUARIO') AS tipo
FROM mysql.user
WHERE user IN ('administrador_sistema','gerente_marketing','analista_datos',
               'empleado_inventario','atencion_cliente','auditor_financiero','visitante',
               'admin_user','marketing_user','inventory_user','support_user','analyst_user')
ORDER BY tipo DESC, cuenta;

-- Permisos otorgados a cada rol
SHOW GRANTS FOR 'administrador_sistema';
SHOW GRANTS FOR 'gerente_marketing';
SHOW GRANTS FOR 'analista_datos';
SHOW GRANTS FOR 'empleado_inventario';
SHOW GRANTS FOR 'atencion_cliente';
SHOW GRANTS FOR 'auditor_financiero';
SHOW GRANTS FOR 'visitante';

-- Permisos efectivos de cada usuario a traves de su rol
SHOW GRANTS FOR 'admin_user'@'%'     USING 'administrador_sistema';
SHOW GRANTS FOR 'marketing_user'@'%' USING 'gerente_marketing';
SHOW GRANTS FOR 'inventory_user'@'%' USING 'empleado_inventario';
SHOW GRANTS FOR 'support_user'@'%'   USING 'atencion_cliente';

-- Prueba del req. 11: analista_datos no tiene DELETE en ninguna tabla
SELECT GRANTEE, TABLE_NAME, PRIVILEGE_TYPE
FROM information_schema.TABLE_PRIVILEGES
WHERE GRANTEE LIKE '%analista_datos%'
  AND PRIVILEGE_TYPE IN ('DELETE','DROP','UPDATE','INSERT');
-- Resultado esperado: conjunto vacio

-- Prueba del req. 14: empleado_inventario solo puede actualizar 2 columnas
SELECT GRANTEE, TABLE_NAME, COLUMN_NAME, PRIVILEGE_TYPE
FROM information_schema.COLUMN_PRIVILEGES
WHERE GRANTEE LIKE '%empleado_inventario%'
ORDER BY COLUMN_NAME;
-- Resultado esperado: solo stock y ubicacion con privilegio UPDATE
