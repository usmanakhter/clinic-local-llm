#include "my_application.h"

#include <cstdlib>

#include <gdk/gdk.h>

int main(int argc, char** argv) {
  // Surface / GNOME HiDPI + Wayland: Flutter's Linux OpenGL embedder often
  // mismatches frame sizes ("Timed out waiting for OpenGL frame…") and the
  // Wayland compositor can kill the process ("Lost connection to device").
  // Default to X11 + integer scale unless the user already overrode env.
  if (getenv("GDK_BACKEND") == nullptr) {
    setenv("GDK_BACKEND", "x11", 0);
  }
  if (getenv("GDK_SCALE") == nullptr) {
    setenv("GDK_SCALE", "1", 0);
  }
  if (getenv("GDK_DPI_SCALE") == nullptr) {
    setenv("GDK_DPI_SCALE", "1", 0);
  }
  // Must run before GTK/GDK opens a display.
  gdk_set_allowed_backends("x11");

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
