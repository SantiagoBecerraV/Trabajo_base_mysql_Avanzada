-- ===========================================
-- TRIGGER

USE ecommerce_db;


-- TABLA DE AUDITORIA
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_auditoria      INT AUTO_INCREMENT PRIMARY KEY,
    id_producto       INT NOT NULL,
    nombre_producto   VARCHAR(150),
    precio_anterior   DECIMAL(12,2),
    precio_nuevo      DECIMAL(12,2),
    diferencia        DECIMAL(12,2),
    porcentaje_cambio DECIMAL(10,2),
    usuario           VARCHAR(100) DEFAULT 'sistema',
    fecha_cambio      DATETIME DEFAULT CURRENT_TIMESTAMP,
    razon_cambio      VARCHAR(255),
    CONSTRAINT fk_logprecio_producto2
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;


DELIMITER $$

-- 1. trg_audit_precio_producto_after_update
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update$$
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NOT (OLD.precio <=> NEW.precio) THEN
        INSERT INTO log_cambios_precio (
            id_producto, nombre_producto, precio_anterior, precio_nuevo,
            diferencia, porcentaje_cambio, usuario, fecha_cambio, razon_cambio
        ) VALUES (
            NEW.id_producto,
            NEW.nombre,
            OLD.precio,
            NEW.precio,
            NEW.precio - OLD.precio,
            -- se protege la division por cero si el precio anterior fuera 0
            ROUND((NEW.precio - OLD.precio) / NULLIF(OLD.precio, 0) * 100, 2),
            CURRENT_USER(),
            NOW(),
            'Cambio registrado automaticamente por trigger'
        );
    END IF;
END$$


-- 2. trg_check_stock_before_insert_venta
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta$$
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock  INT;
    DECLARE v_nombre VARCHAR(150);

    SELECT stock, nombre
      INTO v_stock, v_nombre
      FROM productos
     WHERE id_producto = NEW.id_producto;

    IF v_stock IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El producto indicado no existe';
    END IF;

    IF v_stock < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta';
    END IF;
END$$


-- 3. trg_update_stock_after_insert_venta
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta$$
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
       SET stock = stock - NEW.cantidad
     WHERE id_producto = NEW.id_producto;
END$$


-- 4. trg_prevent_delete_categoria_with_products
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products$$
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_productos INT;

    SELECT COUNT(*)
      INTO v_productos
      FROM productos
     WHERE id_categoria = OLD.id_categoria;

    IF v_productos > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar la categoria: tiene productos asociados';
    END IF;
END$$


-- 5. trg_log_new_customer_after_insert
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert$$
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_clientes (
        id_cliente, nombre, apellido, email, accion, fecha_evento, detalles
    ) VALUES (
        NEW.id_cliente,
        NEW.nombre,
        NEW.apellido,
        NEW.email,
        'REGISTRO',
        NOW(),
        CONCAT('Alta de cliente. Direccion: ', IFNULL(NEW.direccion_envio, 'no registrada'))
    );
END$$


-- 6. trg_update_total_gastado_cliente
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente$$
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> 'Cancelado' THEN
        UPDATE clientes
           SET total_gastado = total_gastado + NEW.total
         WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$


-- 7. trg_set_fecha_modificacion_producto
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto$$
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = NOW();
END$$


-- 8. trg_prevent_negative_stock
DROP TRIGGER IF EXISTS trg_prevent_negative_stock$$
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El stock de un producto no puede quedar en negativo';
    END IF;
END$$


-- 9. trg_capitalize_nombre_cliente
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente$$
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre   = CONCAT(UPPER(LEFT(NEW.nombre, 1)),   LOWER(SUBSTRING(NEW.nombre, 2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
END$$


-- 10. trg_recalculate_total_venta_on_detalle_change
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_change$$
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
       SET total = (
            SELECT IFNULL(SUM(cantidad * precio_unitario_congelado), 0)
              FROM detalle_ventas
             WHERE id_venta = NEW.id_venta
       )
     WHERE id_venta = NEW.id_venta;

    IF OLD.id_venta <> NEW.id_venta THEN
        UPDATE ventas
           SET total = (
                SELECT IFNULL(SUM(cantidad * precio_unitario_congelado), 0)
                  FROM detalle_ventas
                 WHERE id_venta = OLD.id_venta
           )
         WHERE id_venta = OLD.id_venta;
    END IF;
END$$


-- 12. trg_prevent_price_zero_or_less
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less$$
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio IS NULL OR NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El precio de un producto debe ser mayor que cero';
    END IF;
END$$


-- 19. trg_assign_default_category_on_null
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null$$
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NULL THEN
        SET NEW.id_categoria = (
            SELECT id_categoria FROM categorias WHERE nombre = 'General' LIMIT 1
        );
    END IF;
END$$


-- APOYO PARA LAS PRUEBAS
DROP PROCEDURE IF EXISTS sp_probar_error$$
CREATE PROCEDURE sp_probar_error(IN p_sql TEXT, IN p_descripcion VARCHAR(255))
BEGIN
    DECLARE v_mensaje TEXT DEFAULT NULL;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_mensaje = MESSAGE_TEXT;
    END;

    SET @sentencia_prueba = p_sql;
    PREPARE st FROM @sentencia_prueba;
    EXECUTE st;
    DEALLOCATE PREPARE st;

    IF v_mensaje IS NULL THEN
        SELECT p_descripcion AS prueba,
               'FALLO: se esperaba un error y la sentencia paso' AS resultado;
    ELSE
        SELECT p_descripcion AS prueba,
               CONCAT('OK, bloqueado: ', v_mensaje) AS resultado;
    END IF;
END$$

DELIMITER ;


-- VERIFICACION: triggers instalados
SELECT TRIGGER_NAME, EVENT_MANIPULATION AS evento, EVENT_OBJECT_TABLE AS tabla, ACTION_TIMING AS momento
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = 'ecommerce_db'
ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING, TRIGGER_NAME;


-- =====================================================================
-- PRUEBAS DE LOS TRIGGERS

-- --- Trigger 1: auditoria de precios -------------------------------
SELECT precio AS precio_antes FROM productos WHERE id_producto = 1;
UPDATE productos SET precio = 3350000 WHERE id_producto = 1;
SELECT id_producto, precio_anterior, precio_nuevo, diferencia, porcentaje_cambio, usuario
FROM log_cambios_precio ORDER BY id_auditoria DESC LIMIT 1;

-- --- Triggers 2 y 3: control y descuento de stock -------------------
-- Se crea una venta de prueba sobre la que trabajar
INSERT INTO ventas (id_cliente, estado, total) VALUES (3, 'Procesando', 0);
SET @venta_prueba = LAST_INSERT_ID();
SELECT @venta_prueba AS venta_de_prueba_creada;

-- Trigger 2: el producto 4 tiene 8 unidades, se piden 15 -> debe fallar
CALL sp_probar_error(
    CONCAT('INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES (',
           @venta_prueba, ', 4, 15, 240000)'),
    'Trigger 2: rechazar una venta sin stock suficiente');

-- Trigger 3: venta valida, el stock del producto 2 debe bajar en 5
SELECT stock AS stock_producto_2_antes FROM productos WHERE id_producto = 2;
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
VALUES (@venta_prueba, 2, 5, 85000);
SELECT stock AS stock_producto_2_despues FROM productos WHERE id_producto = 2;

-- --- Trigger 4: proteger categorias con productos -------------------
CALL sp_probar_error(
    'DELETE FROM categorias WHERE id_categoria = 1',
    'Trigger 4: impedir borrar una categoria que tiene productos');

-- Una categoria vacia si se puede borrar
INSERT INTO categorias (nombre, descripcion) VALUES ('Juguetes', 'Articulos para ninos');
SET @cat_vacia = LAST_INSERT_ID();
DELETE FROM categorias WHERE id_categoria = @cat_vacia;
SELECT 'Trigger 4: categoria sin productos eliminada correctamente' AS resultado;

-- --- Triggers 5 y 9: alta de cliente, log y capitalizacion ----------
-- Se inserta en minusculas a proposito para ver actuar al trigger 9
INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
VALUES ('juan', 'perez', 'juan.perez@correo.com', '$2y$10$hashdeejemplo123', 'Cra 50 #30-40, Bucaramanga');

SELECT id_cliente, nombre, apellido FROM clientes WHERE email = 'juan.perez@correo.com';
SELECT id_cliente, nombre, apellido, accion, detalles FROM log_clientes ORDER BY id_log DESC LIMIT 1;

-- --- Trigger 6: acumulado de gasto del cliente ----------------------
SELECT total_gastado AS total_gastado_antes FROM clientes WHERE id_cliente = 5;
INSERT INTO ventas (id_cliente, estado, total) VALUES (5, 'Pendiente de Pago', 500000);
SELECT total_gastado AS total_gastado_despues FROM clientes WHERE id_cliente = 5;

-- --- Trigger 7: sello de fecha de modificacion ----------------------
UPDATE productos SET stock = stock WHERE id_producto = 3;
SELECT id_producto, nombre, fecha_creacion, fecha_modificacion
FROM productos WHERE id_producto = 3;

-- --- Trigger 8: bloqueo de stock negativo ---------------------------
CALL sp_probar_error(
    'UPDATE productos SET stock = -50 WHERE id_producto = 2',
    'Trigger 8: impedir stock negativo');

-- --- Trigger 10: recalculo del total de la venta --------------------
SELECT id_venta, total AS total_antes FROM ventas WHERE id_venta = 1;
UPDATE detalle_ventas SET cantidad = 2 WHERE id_detalle = 1;
SELECT id_venta, total AS total_despues FROM ventas WHERE id_venta = 1;

-- --- Trigger 12: bloqueo de precio cero o negativo ------------------
CALL sp_probar_error(
    'UPDATE productos SET precio = 0 WHERE id_producto = 1',
    'Trigger 12: impedir precio cero');
CALL sp_probar_error(
    'UPDATE productos SET precio = -100000 WHERE id_producto = 1',
    'Trigger 12: impedir precio negativo');

-- --- Trigger 19: categoria por defecto ------------------------------
INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_proveedor)
VALUES ('Producto Misterio', 'Producto insertado sin categoria', 150000, 75000, 10, 'MYS-001', 1);

SELECT p.id_producto, p.nombre, p.id_categoria, c.nombre AS categoria_asignada
FROM productos p
JOIN categorias c ON c.id_categoria = p.id_categoria
WHERE p.sku = 'MYS-001';