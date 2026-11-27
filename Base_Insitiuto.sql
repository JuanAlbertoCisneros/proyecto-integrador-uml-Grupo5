-- ============================================================================
-- Proyecto Integrador Grupal - AYDS-I
-- Sistema Integral de Gestión de Atención Universitaria
-- Script DDL: Modelo Lógico Relacional Normalizado (3FN) + Auditoría
-- Motor: Microsoft SQL Server (T-SQL)
-- ============================================================================

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'atencion_universitaria')
BEGIN
    CREATE DATABASE atencion_universitaria;
END
GO

USE atencion_universitaria;
GO

-- 1. Catálogo de Roles y Permisos (Control de Acceso RBAC)
CREATE TABLE rol (
    id_rol INT IDENTITY(1,1) PRIMARY KEY,
    nombre NVARCHAR(50) NOT NULL UNIQUE,
    descripcion NVARCHAR(255) NULL
);
GO

CREATE TABLE permiso (
    id_permiso INT IDENTITY(1,1) PRIMARY KEY,
    codigo NVARCHAR(50) NOT NULL UNIQUE,
    descripcion NVARCHAR(255) NULL
);
GO

-- Resolución de relación Muchos a Muchos (N:M) entre ROL y PERMISO
CREATE TABLE rol_permiso (
    id_rol INT NOT NULL,
    id_permiso INT NOT NULL,
    CONSTRAINT pk_rol_permiso PRIMARY KEY (id_rol, id_permiso),
    CONSTRAINT fk_rol_permiso_rol FOREIGN KEY (id_rol)
        REFERENCES rol(id_rol) ON DELETE CASCADE,
    CONSTRAINT fk_rol_permiso_permiso FOREIGN KEY (id_permiso)
        REFERENCES permiso(id_permiso) ON DELETE CASCADE
);
GO

-- 2. Usuarios del sistema (Personal de atención, Coordinadores, Administradores)
CREATE TABLE usuario (
    id_usuario INT IDENTITY(1,1) PRIMARY KEY,
    id_rol INT NOT NULL,
    nombres NVARCHAR(100) NOT NULL,
    apellidos NVARCHAR(100) NOT NULL,
    correo_institucional NVARCHAR(150) NOT NULL UNIQUE,
    activo BIT NOT NULL DEFAULT 1,
    fecha_creacion DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT fk_usuario_rol FOREIGN KEY (id_rol)
        REFERENCES rol(id_rol)
);
GO

-- 3. Estudiantes (Identificación única institucional)
CREATE TABLE estudiante (
    id_estudiante INT IDENTITY(1,1) PRIMARY KEY,
    carnet NVARCHAR(20) NOT NULL UNIQUE,
    nombres NVARCHAR(100) NOT NULL,
    apellidos NVARCHAR(100) NOT NULL,
    correo_institucional NVARCHAR(150) NOT NULL UNIQUE,
    telefono NVARCHAR(20) NULL,
    carrera NVARCHAR(120) NOT NULL,
    activo BIT NOT NULL DEFAULT 1
);
GO

-- 4. Catálogo de Categorías de Solicitud
CREATE TABLE categoria_solicitud (
    id_categoria INT IDENTITY(1,1) PRIMARY KEY,
    nombre NVARCHAR(80) NOT NULL UNIQUE,
    descripcion NVARCHAR(255) NULL,
    sla_horas INT NOT NULL DEFAULT 48 CONSTRAINT chk_categoria_sla CHECK (sla_horas > 0),
    activa BIT NOT NULL DEFAULT 1
);
GO

-- 5. Solicitudes de Atención Estudiantil
CREATE TABLE solicitud (
    id_solicitud INT IDENTITY(1,1) PRIMARY KEY,
    codigo_seguimiento NVARCHAR(30) NOT NULL UNIQUE,
    id_estudiante INT NOT NULL,
    id_categoria INT NOT NULL,
    id_responsable INT NULL, -- Puede crearse sin asignar inicialmente
    asunto NVARCHAR(150) NOT NULL,
    descripcion NVARCHAR(MAX) NOT NULL,
    estado NVARCHAR(30) NOT NULL DEFAULT 'REGISTRADA'
        CONSTRAINT chk_solicitud_estado CHECK (estado IN ('REGISTRADA', 'ASIGNADA', 'EN_PROCESO', 'CITA_PROGRAMADA', 'CERRADA', 'REABIERTA')),
    prioridad NVARCHAR(20) NOT NULL DEFAULT 'MEDIA'
        CONSTRAINT chk_solicitud_prioridad CHECK (prioridad IN ('BAJA', 'MEDIA', 'ALTA', 'URGENTE')),
    resultado_atencion NVARCHAR(MAX) NULL,
    observaciones_cierre NVARCHAR(MAX) NULL,
    fecha_registro DATETIME2 NOT NULL DEFAULT GETDATE(),
    fecha_cierre DATETIME2 NULL,
    CONSTRAINT fk_solicitud_estudiante FOREIGN KEY (id_estudiante)
        REFERENCES estudiante(id_estudiante),
    CONSTRAINT fk_solicitud_categoria FOREIGN KEY (id_categoria)
        REFERENCES categoria_solicitud(id_categoria),
    CONSTRAINT fk_solicitud_responsable FOREIGN KEY (id_responsable)
        REFERENCES usuario(id_usuario)
);
GO

-- 6. Citas de Atención
CREATE TABLE cita (
    id_cita INT IDENTITY(1,1) PRIMARY KEY,
    id_solicitud INT NOT NULL,
    id_responsable INT NOT NULL,
    fecha_cita DATE NOT NULL,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    modalidad NVARCHAR(20) NOT NULL DEFAULT 'PRESENCIAL'
        CONSTRAINT chk_cita_modalidad CHECK (modalidad IN ('PRESENCIAL', 'VIRTUAL')),
    lugar_o_enlace NVARCHAR(255) NOT NULL,
    estado NVARCHAR(20) NOT NULL DEFAULT 'PROGRAMADA'
        CONSTRAINT chk_cita_estado CHECK (estado IN ('PROGRAMADA', 'REPROGRAMADA', 'COMPLETADA', 'CANCELADA')),
    observaciones NVARCHAR(255) NULL,
    CONSTRAINT chk_cita_horario CHECK (hora_fin > hora_inicio),
    CONSTRAINT fk_cita_solicitud FOREIGN KEY (id_solicitud)
        REFERENCES solicitud(id_solicitud),
    CONSTRAINT fk_cita_responsable FOREIGN KEY (id_responsable)
        REFERENCES usuario(id_usuario)
);
GO

-- Índice para optimizar detección de solapamiento de horarios por responsable
CREATE INDEX idx_cita_responsable_fecha
    ON cita (id_responsable, fecha_cita, hora_inicio, hora_fin);
GO

-- 7. Bitácora / Historial Inmutable de Solicitudes
CREATE TABLE historial_solicitud (
    id_historial INT IDENTITY(1,1) PRIMARY KEY,
    id_solicitud INT NOT NULL,
    id_usuario_accion INT NULL, -- NULL si la acción fue iniciada por el estudiante
    tipo_evento NVARCHAR(40) NOT NULL
        CONSTRAINT chk_historial_evento CHECK (tipo_evento IN (
            'CREACION', 'ASIGNACION', 'REASIGNACION', 'CAMBIO_ESTADO',
            'CITA_PROGRAMADA', 'CITA_MODIFICADA', 'CITA_CANCELADA',
            'CIERRE', 'REAPERTURA_AUTORIZADA'
        )),
    estado_anterior NVARCHAR(30) NULL,
    estado_nuevo NVARCHAR(30) NOT NULL,
    detalle NVARCHAR(MAX) NOT NULL,
    fecha_evento DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT fk_historial_solicitud FOREIGN KEY (id_solicitud)
        REFERENCES solicitud(id_solicitud),
    CONSTRAINT fk_historial_usuario FOREIGN KEY (id_usuario_accion)
        REFERENCES usuario(id_usuario)
);
GO

-- 8. Registro de Notificaciones (Integración con Servicio Externo)
CREATE TABLE notificacion (
    id_notificacion INT IDENTITY(1,1) PRIMARY KEY,
    id_solicitud INT NOT NULL,
    destinatario_correo NVARCHAR(150) NOT NULL,
    tipo_notificacion NVARCHAR(50) NOT NULL,
    mensaje NVARCHAR(MAX) NOT NULL,
    estado_envio NVARCHAR(20) NOT NULL DEFAULT 'PENDIENTE'
        CONSTRAINT chk_notificacion_estado CHECK (estado_envio IN ('PENDIENTE', 'ENVIADA', 'FALLIDA')),
    fecha_creacion DATETIME2 NOT NULL DEFAULT GETDATE(),
    fecha_envio DATETIME2 NULL,
    CONSTRAINT fk_notificacion_solicitud FOREIGN KEY (id_solicitud)
        REFERENCES solicitud(id_solicitud)
);
GO