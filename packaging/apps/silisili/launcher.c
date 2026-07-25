/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Sailfish compositor runs with the hwcomposer Qt/EGL platform. GLFW
 * applications need the Wayland client platform instead. This ELF launcher
 * replaces compositor-only variables before starting the upstream binary.
 */

#define _GNU_SOURCE
#include <stdlib.h>
#include <unistd.h>

#define REAL_PATH "/usr/lib64/silisili/silisili.real"

static const char *strip_vars[] = {
    "EGL_PLATFORM",
    "HYBRIS_EGLPLATFORM",
    "QT_QPA_PLATFORM",
    "QT_QPA_FORCE_HWC2",
    "LD_PRELOAD",
    NULL
};

static const struct { const char *name; const char *value; } set_vars[] = {
    { "EGL_PLATFORM", "wayland" },
    { "HYBRIS_EGLPLATFORM", "wayland" },
    { "QT_QPA_PLATFORM", "wayland" },
    { NULL, NULL }
};

int main(int argc, char *argv[])
{
    int i;

    (void)argc;
    for (i = 0; strip_vars[i] != NULL; i++)
        unsetenv(strip_vars[i]);

    for (i = 0; set_vars[i].name != NULL; i++)
        setenv(set_vars[i].name, set_vars[i].value, 1);

    execve(REAL_PATH, argv, environ);
    _exit(127);
}
