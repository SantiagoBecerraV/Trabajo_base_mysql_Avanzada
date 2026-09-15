-- ===========================================
-- ROLES 
-- CREACION DE ROLES 
USE ecommerce_db;

-- administrador_sistema
CREATE ROLE IF NOT EXISTS 'administrador_sistema';
GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'administrador_sistema';

-- Gerente_Marketing 
CREATE ROLE IF NOT EXISTS 'gerente_marketing';
GRANT SELECT ON ecommerce_db.ventas TO 'gerente_marketing';
GRANT SELECT ON ecommerce_db.clientes TO 'Gerente_Marketing';

-- Analista_Datos 
CREATE ROLE IF NOT EXISTS 'analista_datos';
GRANT SELECT ON ecommerce_db.categorias TO 'analista_datos';
GRANT SELECT ON ecommerce_db.proveedores TO 'analista_datos';
GRANT SELECT ON ecommerce_db.productos TO 'analista_datos';
GRANT SELECT ON ecommerce_db.clientes TO 'analista_datos';
GRANT SELECT ON ecommerce_db.ventas TO 'analista_datos';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'analista_datos';
-- FALTA REVISAR COMO NO PUEDA LEER LAS TABLAS DE AUDITORIA

-- Empleado_Inventario 
CREATE ROLE IF NOT EXISTS 'empleado_inventario';
GRANT UPDATE  (stock, ubicacion) ON ecommerce_dc.productos TO 'empleado_inventario';

-- Atencion_cliente
CREATE ROLE IF NOT EXISTS 'atencion_cliente';
GRANT SELECT ON ecommerce_db.clientes TO 'atencion_cliente';
GRANT SELECT ON ecommerce_db.ventas TO 'atencion_cliente';
-- COMO HACER QUE NO PUEDA MODIFICAR PRECIOS SI SOLO TIENE SELECT

-- Auditor_Financiero 
CREATE ROLE IF NOT EXISTS 'auditor_financiero';
GRANT SELECT ecommerce_db.clientes TO 'auditor_financiero';
GRANT SELECT ecommerce_db.ventas TO 'auditor_financiero';
-- FALA DAR PERMISO DE VER LOGS DE PRECIOS

-- USUARIOS

-- Usuario admin
CREATE USER IF NOT EXISTS 'admin_user'@'%' 
IDENTIFIED BY 'admin123';
GRANT 'administrador_sistema' TO 'admin_user'@'%';
SET DEFAULT ROLE 'administrador_sistema' TO 'admin_user'@'%';

SHOW GRANTS FOR 'admin_user'@'%';

-- Marketing usuario
CREATE USER IF NOT EXISTS 'marketing_user'@'%' 
IDENTIFIED BY 'marketing123';
GRANT 'gerente_marketing' TO 'marketing_user'@'%';
SET DEFAULT ROLE 'gerente_marketing' TO 'marketing_user'@'%';

SHOW GRANTS FOR 'marketing_user'@'%';

-- Usuario Inventario
CREATE USER IF NOT EXISTS 'inventory_user'@'%' 
IDENTIFIED BY 'inventory123';
GRANT 'empleado_inventario' TO 'inventory_user'@'%';
SET DEFAULT ROLE 'empleado_inventario' TO 'inventory_user'@'%';

SHOW GRANTS FOR 'inventory_user'@'%';

-- Usuario support
CREATE USER IF NOT EXISTS 'support_user'@'%' 
IDENTIFIED BY 'support123';
GRANT 'atencion_cliente' TO 'support_user'@'%';
SET DEFAULT ROLE 'atencion_cliente' TO 'support_user'@'%';

SHOW GRANTS FOR 'support_user'@'%';

-- EVITAR ANALISTA DATOS