-- actividad de practica

ALTER TABLE productos ADD COLUMN IF NOT EXISTS fecha_ultima_venta DATETIME NULL;

DELIMITER $$

CREATE TRIGGER trg_actualizar_fecha_ultima_venta $$
AFTER INSERT ON Detalle_Ventas
FOR EACH ROW
BEGIN
	UPDATE productos fecha_ultima_venta
	SET fecha_ultima_venta = NOW()
	Where id_producto = NEW.id_producto
END $$

DELIMITER ;

DELIMITER $$

DROP EVENT IF EXISTS evt_desactivar_productos_obsoletos$$
CREATE EVENT evt_desactivar_productos_obsoletos
ON SCHEDULE EVERY 1 MONTH
	STARTS DATE_FORMAT(NOW() + INTERVAL 1 MONTH, '%Y-%m-01 00:00:00')
ON
BEGIN
	UPDATE productos
	SET activo = 'FALSE'
	WHERE activo = 'TRUE'
		AND(
		fecha_ultima_venta < NOW() - INTERVAL 365 DAY
		OR (fecha_ultima_venta IS NULL AND fecha_creacion < NOW() - INTERVAL 365 DAY)
		); 
END;


DELIMITER ;



-- SEGUNDO PUNTO

CREATE TABLE Auditoria_Precios_Productos(
	id_auditoria INT PRIMARY KEY AUTO_INCREMENT,
	id_producto INT NOT NULL,
	campo_modificado VARCHAR(100) NOT NULL,
	valor_antiguo DECIMAL(10,2) NOT NULL,
	valor_nuevo DECIMAL(10,2) NOT NULL,
	usuario VARCHAR(100) NOT NULL,
	fecha_modificacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
);

DELIMITER $$

DROP TRIGGER IF EXISTS trg_audit_producto_after_update$$
CREATE TRIGGER trg_audit_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
	
	DECLARE v_usuario VARCHAR(100);
	SET v_usuario = CURRENT_USER();
	
	IF OLD.precio <> NEW.precio THEN
		INSERT INTO Auditoria_Precios_Productos(
			id_producto,
			campo_modificado,
			valor_antiguo,
			valor_nuevo,
			usuario,
			fecha_modificacion,
		) VALUES (
			NEW.id_producto,
			'Precio',
			OLD.precio,
			NEW.precio,
			v_usuario,
			NOW()
		);
	END IF;
	
	IF OLD.costo <> NEW.costo THEN
		INSERT INTO Auditoria_Precios_Productos(
			id_producto,
			campo_modificado,
			valor_antiguo,
			valor_nuevo,
			usuario,
			fecha_modificacion,
		) VALUES (
			NEW.id_producto,
			'Costo',
			OLD.costo,
			NEW.costo,
			v_usuario,
			NOW()
		);
	END IF;

END$$
	
DELIMITER ;

-- TERCER EJERCICIO

CREATE TABLE cancelaciones_ventas(
	id_cancelacion INT PRIMARY KEY AUTO_INCREMENT,
	id_venta INT NOT NULL,
	motivo VARCHAR(100) NOT NULL,
	fecha_cancelacion DATE DEFAULT CURRENT_TIMESTAMP,
	CONSTRAINT fk_cancelaciones_ventas
		FOREIGN KEY (id_venta) REFERENCES venrtas(id_venta)
)


DELIMITER $$

CREATE PROCEDURE sp_CancelarVenta(
	IN p_id_venta INT,
	IN p_motivo VARCHAR(200)
)
BEGIN
	
	
END


-- =============================================================================
-- PROYECTO E-COMMERCE: CANCELACIÓN TRANSACCIONAL DE VENTA Y RESTAURACIÓN STOCK
-- Archivo: Cancelacion_Transaccional_Venta.sql
-- =============================================================================

USE ecommerce_db;

-- -----------------------------------------------------------------------------
-- 1. TABLA DE BITÁCORA: Cancelaciones_Ventas
-- -----------------------------------------------------------------------------
-- Registra el motivo y fecha exacta en la que un pedido fue cancelado.
CREATE TABLE IF NOT EXISTS Cancelaciones_Ventas (
    id_cancelacion    INT AUTO_INCREMENT PRIMARY KEY,
    id_venta          INT NOT NULL,
    motivo            VARCHAR(255) NOT NULL,
    fecha_cancelacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_cancelacion_venta
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
);


-- -----------------------------------------------------------------------------
-- 2. PROCEDIMIENTO ALMACENADO: sp_CancelarVenta
-- -----------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_CancelarVenta(
    IN p_id_venta INT,
    IN p_motivo   VARCHAR(255)
)
sp_main: BEGIN
    -- Declaración de variables para validación
    DECLARE v_estado VARCHAR(50);
    DECLARE v_existe INT DEFAULT 0;

    -- Manejador de excepciones SQL (Garantiza el ROLLBACK automático ante cualquier error)
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Ante cualquier fallo durante la ejecución, se revierten todos los cambios
        ROLLBACK;
        RESIGNAL;
    END;

    -- -------------------------------------------------------------------------
    -- VALIDACIONES PREVIAS A LA TRANSACCIÓN
    -- -------------------------------------------------------------------------
    -- 1. Verificar si la venta existe y obtener su estado actual
    SELECT COUNT(*), MAX(estado)
      INTO v_existe, v_estado
      FROM ventas
     WHERE id_venta = p_id_venta;

    -- Si la venta no existe en la base de datos
    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La venta especificada no existe en el sistema.';
    END IF;

    -- 2. Verificar que el estado no sea 'Cancelado' ni 'Entregado'
    IF v_estado = 'Cancelado' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La venta ya se encuentra en estado Cancelado.';
    ELSEIF v_estado = 'Entregado' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No es posible cancelar una venta que ya ha sido Entregada.';
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOQUE TRANSACCIONAL ATÓMICO (ACID)
    -- -------------------------------------------------------------------------
    -- Inicia la transacción explícita
    START TRANSACTION;

        -- PASO A: Restaurar el inventario sumando la cantidad vendida al stock de cada producto.
        -- Se realiza una actualización en lote (UPDATE con JOIN) para optimizar el rendimiento.
        UPDATE productos p
        INNER JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
        SET p.stock = p.stock + dv.cantidad
        WHERE dv.id_venta = p_id_venta;

        -- PASO B: Actualizar el estado de la orden a 'Cancelado'
        UPDATE ventas
        SET estado = 'Cancelado'
        WHERE id_venta = p_id_venta;

        -- PASO C: Registrar la cancelación en la bitácora
        INSERT INTO Cancelaciones_Ventas (id_venta, motivo, fecha_cancelacion)
        VALUES (p_id_venta, p_motivo, NOW());

    -- Si todos los pasos se ejecutan sin errores, se consolidan las modificaciones permanentemente.
    COMMIT;

END$$

DELIMITER ;