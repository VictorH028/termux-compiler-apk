#!/bin/bash

################# Mejoras Implementadas ####################
# 1. Verificación de dependencias mejorada
# 2. Manejo de rutas Java más robusto
# 3. Validación de estructura de proyecto Android
# 4. Mejor manejo de errores y limpieza
# 5. Compatibilidad con diferentes estructuras de proyecto
# 6. Optimización de pasos de compilación

# Configuración inicial
set -euo pipefail
trap 'echo "Error en línea $LINENO. Código de salida: $?" >&2; exit 1' ERR

# Colores para mejor legibilidad
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'




# Dependencias necesarias según Android CLI tools
REQUIRED_TOOLS=("aapt2" "javac" "zip" "unzip")
ANDROID_JAR="android.jar"
ZIPALIGN="zipalign"
APKSIGNER="apksigner"

# Verificar e instalar dependencias faltantes
check_dependencies() {
    local missing=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Faltan herramientas requeridas: ${missing[*]}${NC}"
        echo -e "${YELLOW}Instale las dependencias con su gestor de paquetes antes de continuar.${NC}"
        exit 1
    fi
}

# Configuración de directorios
setup_directories() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    PROJECT_DIR="${1:-}"

    # Validar directorio del proyecto
    if [ -z "$PROJECT_DIR" ]; then
        echo -e "${RED}Error: Debe especificar el directorio del proyecto${NC}"
        echo "Uso: $0 <directorio_del_proyecto>"
        exit 1
    fi

    # Obtener ruta absoluta
    if [[ "$PROJECT_DIR" != /* ]]; then
        PROJECT_DIR="$PWD/$PROJECT_DIR"
    fi
    cd $PROJECT_DIR 
    # Verificar estructura básica de proyecto Android
    local required_dirs=("src" "res")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$PROJECT_DIR/$dir" ]; then
            echo -e "${RED}Error: El directorio no parece un proyecto Android válido (falta $dir/)${NC}"
            exit 1
        fi
    done

    # Verificar AndroidManifest.xml
    if [ ! -f "$PROJECT_DIR/AndroidManifest.xml" ]; then
        echo -e "${RED}Error: No se encontró AndroidManifest.xml${NC}"
        exit 1
    fi

    BUILD_DIR="$PROJECT_DIR/build"
    CLASSES_DIR="$BUILD_DIR/classes"
    mkdir -p "$CLASSES_DIR"
}

# Configurar entorno Java
setup_java_environment() {
    # Intentar detectar JAVA_HOME automáticamente
    if [ -z "${JAVA_HOME:-}" ]; then
        JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))
        export JAVA_HOME
    fi

    if [ ! -d "$JAVA_HOME" ]; then
        echo -e "${RED}Error: No se pudo determinar JAVA_HOME${NC}"
        exit 1
    fi

    export PATH="$JAVA_HOME/bin:$PATH"
    echo -e "${GREEN}Usando Java: $(javac -version 2>&1)${NC}"
}

# Compilar recursos con aapt2
compile_resources() {
    echo -e "${YELLOW}Compilando recursos con aapt2...${NC}"
    
    local resource_files=()
    while IFS= read -r -d $'\0' file; do
        resource_files+=("$file")
    done < <(find res -type f -print0)

    if [ ${#resource_files[@]} -eq 0 ]; then
        echo -e "${RED}Error: No se encontraron archivos de recursos en res/${NC}"
        exit 1
    fi

    aapt2 compile  --dir res -o "$BUILD_DIR/resources.zip" || {
        echo -e "${RED}Error al compilar recursos${NC}"
        exit 1
    }
}

# Enlazar recursos con aapt2
link_resources() {
    echo -e "${YELLOW}Enlazando recursos con aapt2...${NC}"
    
    local android_jar_path="$SCRIPT_DIR/toolz/$ANDROID_JAR"
    if [ ! -f "$android_jar_path" ]; then
        echo -e "${RED}Error: No se encontró $ANDROID_JAR en $SCRIPT_DIR/toolz/${NC}"
        exit 1
    fi

    aapt2 link  \
        -I "$android_jar_path" \
        --manifest AndroidManifest.xml \
        --java "$BUILD_DIR" \
        -o "$BUILD_DIR/linked.apk" \
        "$BUILD_DIR/resources.zip" \
        --auto-add-overlay || {
        echo -e "${RED}Error al enlazar recursos${NC}"
        exit 1
    }
}

# Compilar código Java
compile_java() {
    echo -e "${YELLOW}Compilando código Java...${NC}"
    
    local java_files=()
    while IFS= read -r -d $'\0' file; do
        java_files+=("$file")
    done < <(find src -name "*.java" -print0)

    if [ ${#java_files[@]} -eq 0 ]; then
        echo -e "${RED}Error: No se encontraron archivos Java en src/${NC}"
        exit 1
    fi

    # Buscar archivos R.java generados
    local r_java_files=()
    while IFS= read -r -d $'\0' file; do
        r_java_files+=("$file")
    done < <(find "$BUILD_DIR" -name "R.java" -print0)

    javac --release=9 \
        -d "$CLASSES_DIR" \
        -classpath "$SCRIPT_DIR/toolz/$ANDROID_JAR" \
        "${java_files}" \
        "${r_java_files}" || {
        echo -e "${RED}Error al compilar código Java${NC}"
        exit 1
    }
}

# Convertir a formato DEX
convert_to_dex() {
    echo -e "${YELLOW}Convirtiendo a DEX...${NC}"
    # Usar d8 en lugar de dx despues 
    dx --dex --debug \
        --output="$BUILD_DIR/classes.dex" \
        "$CLASSES_DIR" || {
        echo -e "${RED}Error al convertir a DEX${NC}"
        exit 1
    }
}

# Empaquetar APK final
package_apk() {
    echo -e "${YELLOW}Empaquetando APK...${NC}"
    
    # Agregar classes.dex al APK
    (cd "$BUILD_DIR" && zip -u "linked.apk" "classes.dex") || {
        echo -e "${RED}Error al agregar classes.dex al APK${NC}"
        exit 1
    }

    # Agregar librerías nativas si existen
    if [ -d "$PROJECT_DIR/lib" ]; then #|| [ -d "$PROJECT_DIR/jni" ]; then
        echo -e "${YELLOW}Agregando librerías nativas...${NC}"
        (cd "$PROJECT_DIR" && zip -ur "$BUILD_DIR/linked.apk" "lib/" ) || {
            echo -e "${RED}Error al agregar librerías nativas${NC}"
            exit 1
        }
    fi

    # Alinear APK
    echo -e "${YELLOW}Alineando APK con zipalign...${NC}"
    "$SCRIPT_DIR/toolz/$ZIPALIGN" -f  -p 4 $BUILD_DIR/linked.apk $BUILD_DIR/aligned.apk || {
        echo -e "${RED}Error al alinear APK${NC}"
        exit 1
    }

    # Firmar APK
    echo -e "${YELLOW}Firmando APK...${NC}"
    local keystore_path="$SCRIPT_DIR/key.keystore"
    if [ ! -f "$keystore_path" ]; then
        echo -e "${RED}Error: No se encontró el archivo key.keystore${NC}"
        exit 1
    fi

    "$SCRIPT_DIR/toolz/$APKSIGNER" sign \
        --ks "$keystore_path" \
        --min-sdk-version 21 \
        --ks-pass pass:password \
        --out "$BUILD_DIR/final.apk" \
        "$BUILD_DIR/aligned.apk" || {
        echo -e "${RED}Error al firmar APK${NC}"
        exit 1
    }
}

# Función principal
main() {
    check_dependencies
    setup_directories "$@"
    setup_java_environment
    
    # Limpiar compilaciones anteriores
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    compile_resources
    link_resources
    compile_java
    convert_to_dex
    package_apk

    echo -e "${GREEN}\n¡Compilación completada con éxito!${NC}"
    echo -e "APK final generado en: ${GREEN}$BUILD_DIR/final.apk${NC}"
    
    # Mostrar información básica del APK
    echo -e "\n${YELLOW}Información del APK:${NC}"
    aapt dump badging "$BUILD_DIR/final.apk" | grep -E "package:|launchable-activity:"
}

# Ejecutar función principal
main "$@"
