/* ACTIVIDAD 4 - BASE DE DATOS II: VISTAS, ÍNDICES Y RENDIMIENTO
   Autor: [Jessica Sandy Arteaga]
   Plataforma: Neon / PostgreSQL 16+
*/

-- ==========================================================
-- 0. LIMPIEZA Y PREPARACIÓN (Para pruebas limpias)
-- ==========================================================
DROP VIEW IF EXISTS V_ResumenAcademico;
DROP VIEW IF EXISTS V_CargaDocente;
DROP VIEW IF EXISTS V_EstudiantesRiesgo;
DROP MATERIALIZED VIEW IF EXISTS VM_EstadisticasMateria;
DROP TABLE IF EXISTS Inscripciones;
DROP TABLE IF EXISTS Materia;
DROP TABLE IF EXISTS Profesor;
DROP TABLE IF EXISTS Estudiante;
DROP TABLE IF EXISTS Persona;

-- ==========================================================
-- 1. ESTRUCTURA BASE (DDL MANUAL)
-- ==========================================================

CREATE TABLE Persona (
    dni INT CONSTRAINT PK_Persona PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(20),   -- SENSIBLE
    direccion TEXT,        -- SENSIBLE
    email VARCHAR(100)     -- SENSIBLE
);

CREATE TABLE Estudiante (
    dni INT CONSTRAINT PK_Estudiante PRIMARY KEY,
    legajo VARCHAR(20) CONSTRAINT UQ_Legajo UNIQUE,
    CONSTRAINT FK_Estudiante_Persona FOREIGN KEY (dni) REFERENCES Persona(dni)
);

CREATE TABLE Profesor (
    dni INT CONSTRAINT PK_Profesor PRIMARY KEY,
    especialidad VARCHAR(100),
    mentor_dni INT,
    CONSTRAINT FK_Profesor_Persona FOREIGN KEY (dni) REFERENCES Persona(dni),
    CONSTRAINT FK_Profesor_Mentor FOREIGN KEY (mentor_dni) REFERENCES Profesor(dni)
);

CREATE TABLE Materia (
    id_materia SERIAL CONSTRAINT PK_Materia PRIMARY KEY,
    nombre_materia VARCHAR(100) NOT NULL,
    dni_profesor INT,
    CONSTRAINT FK_Materia_Profesor FOREIGN KEY (dni_profesor) REFERENCES Profesor(dni)
);

CREATE TABLE Inscripciones (
    id_inscripcion SERIAL CONSTRAINT PK_Inscripciones PRIMARY KEY,
    dni_estudiante INT NOT NULL,
    id_materia INT NOT NULL,
    nota INT CONSTRAINT CK_NotaValida CHECK (nota BETWEEN 0 AND 100),
    fecha_inscripcion TIMESTAMP DEFAULT NOW(),
    CONSTRAINT FK_Insc_Estudiante FOREIGN KEY (dni_estudiante) REFERENCES Estudiante(dni),
    CONSTRAINT FK_Insc_Materia FOREIGN KEY (id_materia) REFERENCES Materia(id_materia)
);

-- ==========================================================
-- 2. POBLAMIENTO MASIVO (Para demostrar Optimización)
-- ==========================================================

-- Insertamos 1000 personas de forma masiva
INSERT INTO Persona (dni, nombre, telefono, direccion, email)
SELECT 
    s, 
    'Usuario_' || s, 
    '555-' || s, 
    'Calle Falsa ' || s, 
    'user' || s || '@neon.tech'
FROM generate_series(1, 1000) s;

-- Los primeros 800 son estudiantes
INSERT INTO Estudiante (dni, legajo)
SELECT s, 'LEG-' || s FROM generate_series(1, 800) s;

-- Los últimos 200 son profesores
INSERT INTO Profesor (dni, especialidad)
SELECT s, 'Especialidad_' || s FROM generate_series(801, 1000) s;

-- Materias
INSERT INTO Materia (nombre_materia, dni_profesor)
SELECT 'Materia_' || generate_series, (800 + (generate_series % 200) + 1) FROM generate_series(1, 50)

-- 5000 Inscripciones aleatorias
INSERT INTO Inscripciones (dni_estudiante, id_materia, nota)
SELECT 
    (random() * 799 + 1)::int, 
    (random() * 49 + 1)::int, 
    (random() * 100)::int
FROM generate_series(1, 5000) s;

-- ==========================================================
-- 3. PARTE A: VISTAS LÓGICAS (SEGURIDAD)
-- ==========================================================

-- Punto 1: Ocultar datos sensibles (Solo Nombre, Materia, Nota y Estado)
CREATE OR REPLACE VIEW V_ResumenAcademico AS
SELECT 
    p.nombre AS Estudiante,
    m.nombre_materia AS Materia,
    i.nota,
    CASE 
        WHEN i.nota >= 51 THEN 'APROBADO'
        ELSE 'REPROBADO'
    END AS Estado
FROM Persona p
JOIN Estudiante e ON p.dni = e.dni
JOIN Inscripciones i ON e.dni = i.dni_estudiante
JOIN Materia m ON i.id_materia = m.id_materia;

select * from v_resumenacademico WHERE estado='REPROBADO'; --JESSICA SANDY ARTEAGA

-- Punto 2: Carga Docente
CREATE OR REPLACE VIEW V_CargaDocente AS
SELECT 
    p.nombre AS Profesor,
    COUNT(DISTINCT m.id_materia) AS Total_Materias,
    COUNT(i.id_inscripcion) AS Total_Alumnos
FROM Persona p
JOIN Profesor prof ON p.dni = prof.dni
JOIN Materia m ON prof.dni = m.dni_profesor
LEFT JOIN Inscripciones i ON m.id_materia = i.id_materia
GROUP BY p.nombre;

SELECT * FROM V_CARGADOCENTE; --JESSICA SANDY ARTEAGA

-- Punto 3: Estudiantes en Riesgo
CREATE OR REPLACE VIEW V_EstudiantesRiesgo AS
SELECT * FROM V_ResumenAcademico
WHERE nota < 51;

SELECT * FROM V_ESTUDIANTESRIESGO; --JESSICA SANDY ARTEAGA
-- ==========================================================
-- 4. PARTE C: ANÁLISIS DE RENDIMIENTO (EL "GPS" SQL)
-- ==========================================================

-- ANTES DEL ÍNDICE:
-- Ejecuta esto y mira el "Execution Time"
EXPLAIN ANALYZE 
SELECT * FROM Inscripciones WHERE dni_estudiante = 500; --JESSICA SANDY ARTEAGA

-- CREACIÓN DE ÍNDICES ESTRATÉGICOS
CREATE INDEX IDX_Insc_Estudiante ON Inscripciones(dni_estudiante);
CREATE INDEX IDX_Insc_Materia ON Inscripciones(id_materia);
CREATE INDEX IDX_Persona_Nombre ON Persona(nombre);

-- DESPUÉS DEL ÍNDICE:
-- Notarás que ahora usa "Index Scan" en lugar de "Seq Scan"
EXPLAIN ANALYZE 
SELECT * FROM Inscripciones WHERE dni_estudiante = 500; --JESSICA SANDY ARTEAGA

-- ==========================================================
-- 5. PARTE B: VISTA MATERIALIZADA (RENDIMIENTO BRUTO)
-- ==========================================================

CREATE MATERIALIZED VIEW VM_EstadisticasMateria AS
SELECT 
    m.nombre_materia,
    COUNT(i.id_inscripcion) AS Inscritos,
    ROUND(AVG(i.nota), 2) AS Promedio_General,
    COUNT(CASE WHEN i.nota >= 51 THEN 1 END) * 100.0 / COUNT(i.id_inscripcion) AS Tasa_Aprobacion
FROM Materia m
LEFT JOIN Inscripciones i ON m.id_materia = i.id_materia
GROUP BY m.nombre_materia;

-- DEMOSTRACIÓN DE REFRESH (Uso obligatorio tras cambios en datos base)
REFRESH MATERIALIZED VIEW VM_EstadisticasMateria;

-- Consultar la vista (Es instantánea porque los datos ya están calculados en disco)
SELECT * FROM VM_EstadisticasMateria ORDER BY Tasa_Aprobacion DESC; --JESSICA SANDY ARTEAGA