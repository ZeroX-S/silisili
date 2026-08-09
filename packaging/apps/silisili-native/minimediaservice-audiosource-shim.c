/*
 * Compatibility shim for affected Android 9 bonito Sailfish adaptations.
 *
 * Their libmediaplayerservice references the Sailfish AudioSource recording
 * callback hook while the paired libstagefright omits it. Video decoding does
 * not call this method; exporting a no-op lets the standard minimediaservice
 * register the media services used by droidmedia. This file is built as a
 * dependency-free 32-bit Android-compatible ARM ELF shared object.
 * GPL-3.0-or-later.
 */
__attribute__((visibility("default")))
void sailfish_audiosource_set_read_audio_cb(void *self,
                                            void (*callback)(void *),
                                            void *opaque)
    __asm__("_ZN7android11AudioSource14setReadAudioCbEPFvPvES1_");

void sailfish_audiosource_set_read_audio_cb(void *self,
                                            void (*callback)(void *),
                                            void *opaque)
{
    (void)self;
    (void)callback;
    (void)opaque;
}
