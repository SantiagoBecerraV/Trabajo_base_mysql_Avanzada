-- Proyecto Base de Datos E-commerce
-- Archivo 6: eventos programados (1 al 10)
-- Ejecutar despues del 01

USE ecommerce_db;

SET GLOBAL event_scheduler = ON;


-- ====================================
-- TABLAS
-- ====================================

CREATE TABLE IF NOT EXISTS log_ejecucion_eventos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    nombre_evento VARCHAR(100) NOT NULL,
    filas_afectadas INT,
    fecha_ejecucion DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_ejecucion_eventos_historico LIKE log_ejecucion_eventos;

CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio DATE NOT NULL UNIQUE,
    semana_fin DATE NOT NULL,
    cantidad_ventas INT NOT NULL,
    total_vendido DECIMAL(14,2) NOT NULL,
    fecha_generado DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS niveles_lealtad_clientes (
    id_cliente INT PRIMARY KEY,
    total_gastado DECIMAL(14,2) NOT NULL,
    nivel VARCHAR(20) NOT NULL,
    fecha_calculo DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);

CREATE TABLE IF NOT EXISTS lista_reabastecimiento (
    id_lista INT AUTO_INCREMENT PRIMARY KEY,
    fecha_lista DATE NOT NULL,
    id_producto INT NOT NULL,
    stock_actual INT NOT NULL,
    stock_minimo INT NOT NULL,
    cantidad_sugerida INT NOT NULL,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

CREATE TABLE IF NOT EXISTS resumen_ventas_diarias (
    fecha DATE PRIMARY KEY,
    cantidad_ventas INT NOT NULL,
    total_vendido DECIMAL(14,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS inconsistencias_detectadas (
    id_inconsistencia INT AUTO_INCREMENT PRIMARY KEY,
    tipo VARCHAR(100) NOT NULL,
    id_venta INT NOT NULL,
    fecha_revision DATE NOT NULL
);


-- ====================================
-- EVENTOS
-- ====================================

DELIMITER $$

DROP EVENT IF EXISTS evt_generate_weekly_sales_report$$
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL (7 - WEEKDAY(CURRENT_DATE)) DAY, '06:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'reporte de ventas de la semana anterior'
DO
BEGIN
    -- lunes y domingo de la semana pasada
    DECLARE v_inicio DATE DEFAULT CURRENT_DATE - INTERVAL (WEEKDAY(CURRENT_DATE) + 7) DAY;
    DECLARE v_fin DATE DEFAULT v_inicio + INTERVAL 6 DAY;

    DELETE FROM reporte_ventas_semanales WHERE semana_inicio = v_inicio;

    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, cantidad_ventas, total_vendido)
    SELECT v_inicio, v_fin, COUNT(*), IFNULL(SUM(total), 0)
    FROM ventas
    WHERE estado <> 'Cancelado'
      AND DATE(fecha_venta) BETWEEN v_inicio AND v_fin;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_generate_weekly_sales_report', ROW_COUNT());
END$$


DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily$$
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'borra tablas temporales de trabajo'
DO
BEGIN
    -- la crea evt_recalculate_customer_loyalty_tiers_nightly a las 2am
    DROP TABLE IF EXISTS tmp_gasto_clientes;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_cleanup_temp_tables_daily', 0);
END$$


DROP EVENT IF EXISTS evt_archive_old_logs_monthly$$
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS TIMESTAMP(LAST_DAY(CURRENT_DATE) + INTERVAL 1 DAY, '00:30:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'archiva logs de mas de 6 meses'
DO
BEGIN
    -- misma fecha limite para el INSERT y el DELETE, asi no se pierden filas
    DECLARE v_limite DATETIME DEFAULT NOW() - INTERVAL 6 MONTH;
    DECLARE v_filas INT DEFAULT 0;

    INSERT INTO log_ejecucion_eventos_historico
    SELECT * FROM log_ejecucion_eventos
    WHERE fecha_ejecucion < v_limite;

    SET v_filas = ROW_COUNT();

    DELETE FROM log_ejecucion_eventos
    WHERE fecha_ejecucion < v_limite;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_archive_old_logs_monthly', v_filas);
END$$


DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly$$
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
ENABLE
COMMENT 'desactiva codigos de descuento vencidos'
DO
BEGIN
    UPDATE promociones
    SET activa = FALSE
    WHERE activa = TRUE
      AND fecha_fin < NOW();

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_deactivate_expired_promotions_hourly', ROW_COUNT());
END$$


DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly$$
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'recalcula nivel de lealtad de los clientes'
DO
BEGIN
    DROP TABLE IF EXISTS tmp_gasto_clientes;
    CREATE TABLE tmp_gasto_clientes AS
    SELECT c.id_cliente, IFNULL(SUM(v.total), 0) AS gasto
    FROM clientes c
    LEFT JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
    GROUP BY c.id_cliente;

    DELETE FROM niveles_lealtad_clientes;

    INSERT INTO niveles_lealtad_clientes (id_cliente, total_gastado, nivel)
    SELECT id_cliente, gasto,
        CASE
            WHEN gasto >= 3000000 THEN 'Oro'
            WHEN gasto >= 700000 THEN 'Plata'
            WHEN gasto > 0 THEN 'Bronce'
            ELSE 'Sin nivel'
        END
    FROM tmp_gasto_clientes;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_recalculate_customer_loyalty_tiers_nightly', ROW_COUNT());
END$$


DROP EVENT IF EXISTS evt_generate_reorder_list_daily$$
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 5 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'lista de productos para reabastecer'
DO
BEGIN
    DELETE FROM lista_reabastecimiento WHERE fecha_lista = CURRENT_DATE;

    -- cantidad sugerida: lo que falta para llegar al doble del stock minimo
    INSERT INTO lista_reabastecimiento (fecha_lista, id_producto, stock_actual, stock_minimo, cantidad_sugerida)
    SELECT CURRENT_DATE, id_producto, stock, stock_minimo, (stock_minimo * 2) - stock
    FROM productos
    WHERE activo = TRUE
      AND stock < stock_minimo;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_generate_reorder_list_daily', ROW_COUNT());
END$$


DROP EVENT IF EXISTS evt_rebuild_indexes_weekly$$
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL (7 - WEEKDAY(CURRENT_DATE)) DAY, '04:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'reconstruye indices de las tablas principales'
DO
BEGIN
    OPTIMIZE TABLE productos;
    OPTIMIZE TABLE clientes;
    OPTIMIZE TABLE ventas;
    OPTIMIZE TABLE detalle_ventas;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_rebuild_indexes_weekly', 0);
END$$


DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly$$
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 1 QUARTER
STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'desactiva cuentas sin actividad en mas de un año'
DO
BEGIN
    -- si nunca compro, se cuenta desde la fecha de registro
    UPDATE clientes
    SET activo = FALSE
    WHERE activo = TRUE
      AND IFNULL(fecha_ultimo_pedido, fecha_registro) < NOW() - INTERVAL 1 YEAR;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_suspend_inactive_accounts_quarterly', ROW_COUNT());
END$$


DROP EVENT IF EXISTS evt_aggregate_daily_sales_data$$
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 15 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'resumen diario de ventas'
DO
BEGIN
    DECLARE v_ayer DATE DEFAULT CURRENT_DATE - INTERVAL 1 DAY;

    DELETE FROM resumen_ventas_diarias WHERE fecha = v_ayer;

    INSERT INTO resumen_ventas_diarias (fecha, cantidad_ventas, total_vendido)
    SELECT v_ayer, COUNT(*), IFNULL(SUM(total), 0)
    FROM ventas
    WHERE estado <> 'Cancelado'
      AND DATE(fecha_venta) = v_ayer;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_aggregate_daily_sales_data', ROW_COUNT());
END$$


DROP EVENT IF EXISTS evt_check_data_consistency_nightly$$
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 1 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'busca inconsistencias en ventas'
DO
BEGIN
    DECLARE v_filas INT DEFAULT 0;

    DELETE FROM inconsistencias_detectadas WHERE fecha_revision = CURRENT_DATE;

    INSERT INTO inconsistencias_detectadas (tipo, id_venta, fecha_revision)
    SELECT 'Venta sin detalle', v.id_venta, CURRENT_DATE
    FROM ventas v
    LEFT JOIN detalle_ventas d ON d.id_venta = v.id_venta
    WHERE d.id_detalle IS NULL;

    SET v_filas = ROW_COUNT();

    INSERT INTO inconsistencias_detectadas (tipo, id_venta, fecha_revision)
    SELECT 'Total no cuadra con el detalle', v.id_venta, CURRENT_DATE
    FROM ventas v
    JOIN detalle_ventas d ON d.id_venta = v.id_venta
    GROUP BY v.id_venta, v.total
    HAVING v.total <> SUM(d.cantidad * d.precio_unitario_congelado);

    SET v_filas = v_filas + ROW_COUNT();

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_check_data_consistency_nightly', v_filas);
END$$

DELIMITER ;


-- ====================================
-- VERIFICAR
-- ====================================

SELECT EVENT_NAME, STATUS, INTERVAL_VALUE, INTERVAL_FIELD, STARTS, LAST_EXECUTED
FROM information_schema.EVENTS
WHERE EVENT_SCHEMA = 'ecommerce_db'
ORDER BY EVENT_NAME;

-- para probar un evento sin esperar su horario:
--   ALTER EVENT nombre_evento ON SCHEDULE AT CURRENT_TIMESTAMP + INTERVAL 10 SECOND;
-- despues se vuelve a correr este archivo para dejarlo con su horario normal