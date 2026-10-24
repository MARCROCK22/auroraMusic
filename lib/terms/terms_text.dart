// BORRADOR: texto redactado sin revisión legal. Debe revisarlo un abogado antes
// de publicar una versión con él. Al cambiar el contenido, sube kTermsVersion
// para que todos los usuarios vuelvan a aceptarlo.

/// Versión del texto. Cambiarla obliga a volver a aceptar.
const kTermsVersion = '2026-10-24';

/// Fecha legible de esta versión.
const kTermsDate = '19 de octubre de 2026';

class TermsSection {
  const TermsSection(this.title, this.body);
  final String title;
  final String body;
}

const kTermsIntro =
    'Antes de usar Aurora Music, lee estas condiciones. Si no estás de acuerdo, '
    'puedes rechazarlas y la aplicación se cerrará.';

const kTermsSections = <TermsSection>[
  TermsSection(
    '1. Qué es Aurora',
    'Aurora Music es un reproductor de música personal para Windows y Android. '
        'Reproduce archivos de tu dispositivo y contenido de servicios de '
        'terceros, y te ayuda a organizar tu biblioteca, tus listas y tu cola.',
  ),
  TermsSection(
    '2. Servicios de terceros',
    'Aurora puede buscar y reproducir contenido de plataformas como YouTube y '
        'YouTube Music. Aurora no tiene afiliación, patrocinio ni aprobación de '
        'esas plataformas ni de sus titulares de derechos. Tú eres responsable '
        'de cumplir sus condiciones de servicio y las leyes de tu país. Esos '
        'servicios pueden cambiar o dejar de funcionar sin aviso, y Aurora no '
        'garantiza que un contenido esté siempre disponible.',
  ),
  TermsSection(
    '3. Descargas y derechos de autor',
    'Aurora solo descarga contenido cuando tú lo pides de forma explícita, y '
        'únicamente para tu uso personal y privado. No debes redistribuir, '
        'vender ni publicar lo descargado. Asegúrate de tener derecho a '
        'descargar y conservar cada contenido; la responsabilidad es tuya.',
  ),
  TermsSection(
    '4. Tus datos se quedan en tu dispositivo',
    'Tu biblioteca, tus listas, tus ajustes, tu historial y el perfil de '
        'gustos del DJ, junto con su base de datos de similitud musical, se '
        'guardan y se calculan en tu dispositivo. Aurora no los envía a '
        'servidores propios ni los vende; lo único que sale de tu dispositivo '
        'es lo que actives tú en la sección 6. Puedes borrarlos desinstalando la '
        'aplicación o eliminando sus datos locales.',
  ),
  TermsSection(
    '5. Privacidad y conexiones de red',
    'Para funcionar, Aurora se conecta a internet: consulta servicios de '
        'terceros para buscar música, obtener el audio, letras, carátulas y '
        'recomendaciones, y comprueba si hay actualizaciones. Esos servicios '
        'ven tu dirección IP y los datos propios de cada petición, y se rigen '
        'por sus propias políticas de privacidad. Compartir tu historial con '
        'Last.fm es opcional y está desactivado por defecto (ver la '
        'sección 6).',
  ),
  TermsSection(
    '6. Last.fm (opcional)',
    'Last.fm es un servicio de Last.fm Ltd. Está desactivado por defecto y '
        'solo funciona si conectas tu propia cuenta en Ajustes e '
        'enciendes el interruptor. Tu contraseña solo se envía a Last.fm, por '
        'HTTPS, para iniciar sesión; Aurora no la guarda. Lo único que '
        'conserva es una clave de sesión, en el almacenamiento seguro del '
        'sistema, nunca en texto plano. Con el interruptor encendido Aurora '
        'envía a Last.fm lo que escuchas: artista, título, álbum si se conoce, '
        'duración y la hora de inicio de la reproducción. No se envían '
        'escuchas de menos de 30 segundos ni durante una Jam. Aurora también '
        'pide a Last.fm canciones similares a la que suena y las usa para '
        'sugerirte música; después Aurora busca esas canciones en YouTube. '
        'Tú lo controlas: puedes desconectar tu cuenta en Ajustes, lo que '
        'borra la sesión y las escuchas pendientes de enviar, o revocar el '
        'acceso de Aurora en tu cuenta de Last.fm. Last.fm trata esos datos '
        'bajo sus propios términos y su propia política de privacidad '
        '(last.fm); léelos antes de activarlo. Tus escuchas son públicas en '
        'tu perfil de Last.fm según los ajustes de privacidad que tengas allí. '
        'Aurora no vende tus datos.',
  ),
  TermsSection(
    '7. Artistas que sigues',
    'La lista de artistas que sigues se guarda solo en tu dispositivo. '
        'Aurora no la envía a ningún servidor propio ni la comparte.',
  ),
  TermsSection(
    '8. Jam y funciones de red',
    'La función Jam permite escuchar junto a otras personas conectándote a '
        'ellas. Al usarla, comparte con los demás participantes la información '
        'necesaria para sincronizar la reproducción (por ejemplo, qué suena y '
        'un nombre). Solo compártela con personas de confianza. No uses estas '
        'funciones para acosar, para infringir derechos de terceros ni para '
        'actividades ilegales.',
  ),
  TermsSection(
    '9. Sin garantía',
    'Aurora se ofrece «tal cual», sin garantías de ningún tipo, expresas o '
        'implícitas, incluidas las de disponibilidad, ausencia de errores o '
        'idoneidad para un fin concreto. En la medida que permita la ley, los '
        'autores no responden por pérdidas de datos, interrupciones del '
        'servicio ni daños derivados del uso de la aplicación.',
  ),
  TermsSection(
    '10. Cambios de versión',
    'Estas condiciones pueden cambiar con nuevas versiones de Aurora. Cuando '
        'cambien, se te pedirá aceptarlas de nuevo antes de seguir usando la '
        'aplicación. Si no las aceptas, no podrás usarla.',
  ),
  TermsSection(
    '11. Aceptación',
    'Al pulsar «Aceptar» confirmas que has leído estas condiciones y que las '
        'aceptas. Se guardará en tu dispositivo la versión aceptada y la '
        'fecha. Si pulsas «Rechazar» o cierras esta ventana sin elegir, la '
        'aplicación se cierra y no se guarda nada.',
  ),
];
