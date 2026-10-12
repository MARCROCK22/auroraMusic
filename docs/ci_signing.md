# Compilaciones y firma

Android conserva su identidad existente. No se genera otra keystore ni se copia
la configuración local a los worktrees. El propietario debe guardar una copia
segura de la keystore original fuera de Git y del chat.

El job `build` de `.github/workflows/android.yml` compila una versión ARM64 firmada
en pushes a `main` o al ejecutar manualmente `build_type: release`. Antes de
compilar exige estos cuatro secretos del repositorio:

| Secreto | Contenido |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Archivo de la keystore existente codificado en Base64 |
| `ANDROID_STORE_PASSWORD` | Contraseña de esa keystore |
| `ANDROID_KEY_ALIAS` | Alias de la clave existente |
| `ANDROID_KEY_PASSWORD` | Contraseña de esa clave |

Se configuran en GitHub → repositorio → **Settings → Secrets and variables →
Actions → New repository secret**. Los cuatro secretos se actualizaron y se
comprobaron con GitHub CLI autenticado el 12 de octubre de 2026 en
`kaz-py/auroraMusic`, utilizando la identidad local existente. Se validaron
la keystore y el acceso a su clave sin exponer sus valores. No falta ninguno
de los cuatro secretos Android. El workflow
enumera solo los nombres ausentes y falla antes de firmar. Si se prefieren
Environment Secrets, el propietario debe configurar un environment y asociarlo
al job `build`; esta configuración usa Repository Secrets directamente.

`ci_android_signing.ps1` restaura el archivo exclusivamente en
`RUNNER_TEMP/aurora-signing/release.jks`, con ACL sin herencia y acceso para el
usuario del runner. No escribe contraseñas en `key.properties`. Gradle recibe
las tres credenciales y `ANDROID_KEYSTORE_PATH` únicamente en el paso de build.
Un paso `always()` elimina el directorio temporal incluso si falla el build.
Los artefactos contienen solamente APK y checksum. La verificación de firma,
manifest de release y alineación de páginas de 16 KB permanece obligatoria.
Una keystore con Base64 válido pero formato, alias o contraseña incorrectos
fallará al firmar; el script no pretende validar criptografía.

Para compilar localmente, Gradle mantiene el soporte de `android/key.properties`
ignorado por Git mediante `java.util.Properties`. Debe contener `storeFile`,
`storePassword`, `keyAlias` y `keyPassword`, y `storeFile` debe existir. Se aplican
las reglas de escape de Properties (por ejemplo, barras `/` para rutas Windows).
Una petición de tareas de release sin configuración válida falla expresamente;
debug sigue usando la firma de desarrollo de Android. No compartir este archivo.

Pull requests y ejecuciones manuales `build_type: debug` usan un job sin secretos
de release. Su artefacto se llama `Aurora-Android-ARM64-debug`. Windows valida y
empaqueta en PR, pushes a `main` y ejecución manual. Ambos workflows mantienen
Flutter 3.38.8 y permisos `contents: read`, sin persistir credenciales de checkout.

Windows no tiene una identidad Authenticode configurada: su archivo ZIP de
release contiene ejecutables sin firma Authenticode. No se presentan como
firmados ni se inventa un certificado. La firma Android no autentica Windows.

Comprobación local sin secretos reales:

```powershell
./scripts/test_ci_android_signing.ps1
```

Fuentes: [GitHub Actions: secretos](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
y [Android: firma de aplicaciones](https://developer.android.com/studio/publish/app-signing).
