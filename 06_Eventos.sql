-- =====================================================================
-- PROYECTO BASE DE DATOS AVANZADA - E-COMMERCE
-- Archivo 06: Eventos Programados
--
-- Requisito previo: haber ejecutado 01_Esquema_y_Datos.sql
-- =====================================================================

USE ecommerce_db;

-- El planificador viene apagado por defecto en MySQL. Sin esta linea
-- los eventos se crean pero NUNCA se ejecutan.
-- Requiere el privilegio SUPER o EVENT_SCHEDULER_ADMIN.
SET GLOBAL event_scheduler = ON;


-- =====================================================================
-- TABLA DE REPORTES
-- Ya viene creada en 01_Esquema_y_Datos.sql. Se repite con
-- IF NOT EXISTS para que el archivo sea autocontenido.
-- =====================================================================

CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte      INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio   DATE NOT NULL UNIQUE,
    semana_fin      DATE NOT NULL,
    cantidad_ventas INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL,
    fecha_generado  DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;


DELIMITER $$

-- =====================================================================
-- 1. evt_generate_weekly_sales_report
--    Cada lunes a las 06:00 consolida las ventas de la semana anterior.
--    El DELETE previo hace la operacion idempotente: si el evento se
--    reintenta, actualiza la fila en lugar de duplicarla.
-- =====================================================================
DROP EVENT IF EXISTS evt_generate_weekly_sales_report$$
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(CURRENT_DATE + INTERVAL (7 - WEEKDAY(CURRENT_DATE)) DAY, '06:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Reporte consolidado de las ventas de la semana anterior'
DO
BEGIN
    -- WEEKDAY() devuelve 0 para lunes, asi que esto ubica el lunes pasado
    DECLARE v_inicio DATE DEFAULT CURRENT_DATE - INTERVAL (WEEKDAY(CURRENT_DATE) + 7) DAY;
    DECLARE v_fin    DATE DEFAULT CURRENT_DATE - INTERVAL (WEEKDAY(CURRENT_DATE) + 1) DAY;

    DELETE FROM reporte_ventas_semanales WHERE semana_inicio = v_inicio;

    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, cantidad_ventas, total_vendido)
    SELECT v_inicio, v_fin, COUNT(*), IFNULL(SUM(total), 0)
      FROM ventas
     WHERE estado <> 'Cancelado'
       AND DATE(fecha_venta) BETWEEN v_inicio AND v_fin;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_generate_weekly_sales_report', ROW_COUNT());
END$$


-- =====================================================================
-- 2. evt_cleanup_temp_tables_daily
--    Borra a las 03:00 las tablas temporales de trabajo que dejan
--    otros procesos, en particular tmp_gasto_clientes, que crea el
--    evento 5 a las 02:00.
-- =====================================================================
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily$$
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY
    STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Limpieza diaria de tablas temporales de trabajo'
DO
BEGIN
    DROP TABLE IF EXISTS tmp_gasto_clientes;
    DROP TABLE IF EXISTS tmp_ranking_productos;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_cleanup_temp_tables_daily', 0);
END$$


-- =====================================================================
-- 3. evt_archive_old_logs_monthly
--    El dia 1 de cada mes mueve al historico los registros de bitacora
--    con mas de 6 meses.
--    La fecha limite se calcula UNA vez en una variable: si se usara
--    NOW() en el INSERT y otra vez en el DELETE, los registros creados
--    entre ambas sentencias se borrarian sin haberse archivado.
-- =====================================================================
DROP EVENT IF EXISTS evt_archive_old_logs_monthly$$
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH
    STARTS TIMESTAMP(LAST_DAY(CURRENT_DATE) + INTERVAL 1 DAY, '00:30:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Archiva en el historico los logs de mas de 6 meses'
DO
BEGIN
    DECLARE v_limite DATETIME DEFAULT NOW() - INTERVAL 6 MONTH;
    DECLARE v_filas  INT DEFAULT 0;

    INSERT INTO log_ejecucion_eventos_historico
    SELECT * FROM log_ejecucion_eventos WHERE fecha_ejecucion < v_limite;

    SET v_filas = ROW_COUNT();

    DELETE FROM log_ejecucion_eventos WHERE fecha_ejecucion < v_limite;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_archive_old_logs_monthly', v_filas);
END$$


-- =====================================================================
-- 4. evt_deactivate_expired_promotions_hourly
--    Cada hora desactiva las promociones cuya vigencia ya vencio.
-- =====================================================================
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly$$
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
    STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Desactiva los codigos de descuento vencidos'
DO
BEGIN
    UPDATE promociones
       SET activa = FALSE
     WHERE activa = TRUE
       AND fecha_fin < NOW();

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_deactivate_expired_promotions_hourly', ROW_COUNT());
END$$


-- =====================================================================
-- 5. evt_recalculate_customer_loyalty_tiers_nightly
--    Cada noche a las 02:00 reclasifica a los clientes en Oro, Plata,
--    Bronce o Sin nivel segun su gasto historico.
--    El calculo pesado se hace sobre una tabla temporal de trabajo que
--    limpia despues el evento 2.
-- =====================================================================
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly$$
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY
    STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Recalcula el nivel de lealtad de cada cliente'
DO
BEGIN
    DROP TABLE IF EXISTS tmp_gasto_clientes;
    CREATE TABLE tmp_gasto_clientes AS
    SELECT c.id_cliente, IFNULL(SUM(v.total), 0) AS gasto
      FROM clientes c
      LEFT JOIN ventas v
             ON v.id_cliente = c.id_cliente
            AND v.estado <> 'Cancelado'
     GROUP BY c.id_cliente;

    DELETE FROM niveles_lealtad_clientes;

    INSERT INTO niveles_lealtad_clientes (id_cliente, total_gastado, nivel)
    SELECT id_cliente,
           gasto,
           CASE
               WHEN gasto >= 3000000 THEN 'Oro'
               WHEN gasto >=  700000 THEN 'Plata'
               WHEN gasto >       0  THEN 'Bronce'
               ELSE 'Sin nivel'
           END
      FROM tmp_gasto_clientes;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_recalculate_customer_loyalty_tiers_nightly', ROW_COUNT());
END$$


-- =====================================================================
-- 6. evt_generate_reorder_list_daily
--    Cada dia a las 05:00 arma la lista de compras para el area de
--    inventario. La cantidad sugerida lleva el stock hasta el doble
--    del minimo, para no volver a quedar al limite de inmediato.
-- =====================================================================
DROP EVENT IF EXISTS evt_generate_reorder_list_daily$$
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY
    STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 5 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Genera la lista diaria de productos a reabastecer'
DO
BEGIN
    DELETE FROM lista_reabastecimiento WHERE fecha_lista = CURRENT_DATE;

    INSERT INTO lista_reabastecimiento
        (fecha_lista, id_producto, stock_actual, stock_minimo, cantidad_sugerida)
    SELECT CURRENT_DATE, id_producto, stock, stock_minimo, (stock_minimo * 2) - stock
      FROM productos
     WHERE activo = TRUE
       AND stock < stock_minimo;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_generate_reorder_list_daily', ROW_COUNT());
END$$


-- =====================================================================
-- 7. evt_rebuild_indexes_weekly
--    Cada lunes a las 04:00 reorganiza las tablas mas usadas.
--    En InnoDB, OPTIMIZE TABLE reconstruye la tabla y sus indices, lo
--    que recupera espacio y actualiza las estadisticas del optimizador.
-- =====================================================================
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly$$
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(CURRENT_DATE + INTERVAL (7 - WEEKDAY(CURRENT_DATE)) DAY, '04:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Reconstruye los indices de las tablas principales'
DO
BEGIN
    OPTIMIZE TABLE productos;
    OPTIMIZE TABLE clientes;
    OPTIMIZE TABLE ventas;
    OPTIMIZE TABLE detalle_ventas;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_rebuild_indexes_weekly', 0);
END$$


-- =====================================================================
-- 8. evt_suspend_inactive_accounts_quarterly
--    Cada trimestre desactiva las cuentas sin actividad en mas de un
--    anio. Si el cliente nunca compro, se mide desde su registro.
--    Se desactiva (activo = FALSE), no se borra: las ventas historicas
--    deben seguir apuntando a un cliente valido.
-- =====================================================================
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly$$
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 1 QUARTER
    STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Desactiva cuentas de clientes sin actividad en mas de un anio'
DO
BEGIN
    UPDATE clientes
       SET activo = FALSE
     WHERE activo = TRUE
       AND IFNULL(fecha_ultimo_pedido, fecha_registro) < NOW() - INTERVAL 1 YEAR;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_suspend_inactive_accounts_quarterly', ROW_COUNT());
END$$


-- =====================================================================
-- 9. evt_aggregate_daily_sales_data
--    Cada dia a las 00:15 consolida las ventas del dia anterior en una
--    tabla de resumen. Los reportes leen de ahi en vez de recorrer
--    ventas y detalle_ventas completas cada vez.
-- =====================================================================
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data$$
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY
    STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 15 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Consolida el resumen de ventas del dia anterior'
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


-- =====================================================================
-- 10. evt_check_data_consistency_nightly
--     Cada noche a la 01:00 busca dos problemas clasicos: ventas sin
--     ninguna linea de detalle, y ventas cuyo total no coincide con la
--     suma de su detalle.
-- =====================================================================
DROP EVENT IF EXISTS evt_check_data_consistency_nightly$$
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY
    STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 1 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Revision nocturna de consistencia de los datos de ventas'
DO
BEGIN
    DECLARE v_filas INT DEFAULT 0;

    DELETE FROM inconsistencias_detectadas WHERE fecha_revision = CURRENT_DATE;

    INSERT INTO inconsistencias_detectadas (tipo, id_venta, fecha_revision)
    SELECT 'Venta sin lineas de detalle', v.id_venta, CURRENT_DATE
      FROM ventas v
      LEFT JOIN detalle_ventas d ON d.id_venta = v.id_venta
     WHERE d.id_detalle IS NULL;

    SET v_filas = ROW_COUNT();

    INSERT INTO inconsistencias_detectadas (tipo, id_venta, fecha_revision)
    SELECT 'Total no coincide con el detalle', v.id_venta, CURRENT_DATE
      FROM ventas v
      JOIN detalle_ventas d ON d.id_venta = v.id_venta
     GROUP BY v.id_venta, v.total
    HAVING v.total <> SUM(d.cantidad * d.precio_unitario_congelado);

    SET v_filas = v_filas + ROW_COUNT();

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_check_data_consistency_nightly', v_filas);
END$$

DELIMITER ;


-- =====================================================================
-- VERIFICACION
-- =====================================================================

SELECT @@global.event_scheduler AS planificador_de_eventos;

SELECT EVENT_NAME                                        AS evento,
       STATUS                                            AS estado,
       CONCAT(INTERVAL_VALUE, ' ', INTERVAL_FIELD)       AS frecuencia,
       STARTS                                            AS primera_ejecucion,
       LAST_EXECUTED                                     AS ultima_ejecucion
FROM information_schema.EVENTS
WHERE EVENT_SCHEMA = 'ecommerce_db'
ORDER BY EVENT_NAME;


-- =====================================================================
-- COMO PROBAR UN EVENTO SIN ESPERAR SU HORARIO
--
-- Los eventos de este archivo estan programados para madrugada o para
-- el proximo lunes. Para verlos correr de inmediato, se reprograma el
-- evento a una ejecucion unica dentro de unos segundos:
--
--   ALTER EVENT evt_generate_reorder_list_daily
--       ON SCHEDULE AT CURRENT_TIMESTAMP + INTERVAL 5 SECOND;
--
-- Se espera, y se revisa la bitacora:
--
--   SELECT * FROM log_ejecucion_eventos ORDER BY id_log DESC;
--   SELECT * FROM lista_reabastecimiento;
--
-- Al terminar, se vuelve a ejecutar este archivo para devolver todos
-- los eventos a su horario normal.
-- =====================================================================
