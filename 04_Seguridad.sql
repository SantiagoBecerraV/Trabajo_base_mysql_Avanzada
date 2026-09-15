-- ===========================================
-- ROLES 
-- CREACION DE ROLES 

USE ecommerce_db;

-- 1. Administrador_Sistema 
CREATE ROLE IF NOT EXISTS 'administrador_sistema';
GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'administrador_sistema';

-- 2. Gerente_Marketing
CREATE ROLE IF NOT EXISTS 'gerente_marketing';
GRANT SELECT ON ecommerce_db.ventas TO 'gerente_marketing';
GRANT SELECT ON ecommerce_db.clientes TO 'gerente_marketing';

-- 3. Analista_Datos 
CREATE ROLE IF NOT EXISTS 'analista_datos';
GRANT SELECT ON ecommerce_db.categorias TO 'analista_datos';
GRANT SELECT ON ecommerce_db.proveedores TO 'analista_datos';
GRANT SELECT ON ecommerce_db.productos TO 'analista_datos';
GRANT SELECT ON ecommerce_db.clientes TO 'analista_datos';
GRANT SELECT ON ecommerce_db.ventas TO 'analista_datos';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'analista_datos';
-- NO tiene acceso a: auditoria_precios, log_clientes, log_fecha_modificacion

-- 4. Empleado_Inventario 
CREATE ROLE IF NOT EXISTS 'empleado_inventario';
GRANT SELECT ON ecommerce_db.productos TO 'empleado_inventario';
GRANT UPDATE (stock) ON ecommerce_db.productos TO 'empleado_inventario';

-- 5. Atencion_Cliente 
CREATE ROLE IF NOT EXISTS 'atencion_cliente';
GRANT SELECT ON ecommerce_db.clientes TO 'atencion_cliente';
GRANT SELECT ON ecommerce_db.ventas TO 'atencion_cliente';
-- Solo SELECT, por eso no puede modificar precios

-- 6. Auditor_Financiero 
CREATE ROLE IF NOT EXISTS 'auditor_financiero';
GRANT SELECT ON ecommerce_db.ventas TO 'auditor_financiero';
GRANT SELECT ON ecommerce_db.productos TO 'auditor_financiero';
GRANT SELECT ON ecommerce_db.auditoria_precios TO 'auditor_financiero';


-- 7. admin_user
CREATE USER IF NOT EXISTS 'admin_user'@'%' IDENTIFIED BY 'admin123';
GRANT 'administrador_sistema' TO 'admin_user'@'%';
SET DEFAULT ROLE 'administrador_sistema' TO 'admin_user'@'%';

-- 8. marketing_user
CREATE USER IF NOT EXISTS 'marketing_user'@'%' IDENTIFIED BY 'marketing123';
GRANT 'gerente_marketing' TO 'marketing_user'@'%';
SET DEFAULT ROLE 'gerente_marketing' TO 'marketing_user'@'%';

-- 9. inventory_user
CREATE USER IF NOT EXISTS 'inventory_user'@'%' IDENTIFIED BY 'inventory123';
GRANT 'empleado_inventario' TO 'inventory_user'@'%';
SET DEFAULT ROLE 'empleado_inventario' TO 'inventory_user'@'%';

-- 10. support_user
CREATE USER IF NOT EXISTS 'support_user'@'%' IDENTIFIED BY 'support123';
GRANT 'atencion_cliente' TO 'support_user'@'%';
SET DEFAULT ROLE 'atencion_cliente' TO 'support_user'@'%';



-- 11. Impedir DELETE y TRUNCATE a Analista_Datos
-- (ya no los tiene)

-- 12. Otorgar al rol Gerente_Marketing 
-- (No se crearon los procedimientos)
GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_reporte_ventas_mes TO 'gerente_marketing';
GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_reporte_clientes_activos TO 'gerente_marketing';


-- 13. Luego crea la vista

DROP VIEW IF EXISTS v_info_clientes_basica;
CREATE VIEW v_info_clientes_basica AS
SELECT 
    id_cliente,
    CONCAT(nombre, ' ', apellido) AS nombre_completo,
    email,
    fecha_registro
FROM clientes;

-- Dar acceso al rol
GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'atencion_cliente';


-- 14. Revocar UPDATE en columna precio a Empleado_Inventario

-- En el trabajo no se pedir darle ese permiso a empleadp inventario señor Cristian diaz
REVOKE UPDATE (precio) ON ecommerce_db.productos FROM 'empleado_inventario';


SELECT * FROM mysql.user WHERE user IN ('admin_user', 'marketing_user', 'inventory_user', 'support_user');

-- usuarios conectados
SHOW PROCESSLIST;

