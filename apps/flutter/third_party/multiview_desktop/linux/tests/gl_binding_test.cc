#include "../mvd_linux_gl_binding.h"
#include <gdk/gdkx.h>
#include <epoxy/egl.h>
#include <epoxy/glx.h>
#include <cassert>
#include <cstdio>

struct RealizeBinding { EGLDisplay display; EGLContext context; bool bound = false; int cleanup_calls = 0; };
static void BindPlatform(RealizeBinding* state) {
  assert(eglBindAPI(EGL_OPENGL_ES_API));
  state->bound = eglMakeCurrent(state->display, EGL_NO_SURFACE, EGL_NO_SURFACE, state->context);
  assert(state->bound);
}
// Reproduce the SDK's compositor-shader constructor using real EGL calls in a
// GTK realize handler. No rendering engine or application assets are started.
static void Realize(GtkWidget* container, RealizeBinding* binding) {
  GtkWidget* child = gtk_drawing_area_new();
  g_signal_connect(child, "realize", G_CALLBACK(+[](GtkWidget*, gpointer data) {
    BindPlatform(static_cast<RealizeBinding*>(data));
  }), binding);
  gtk_container_add(GTK_CONTAINER(container), child);
  gtk_widget_realize(child);
  gtk_widget_destroy(child);
}
int main(int argc, char** argv) {
  assert(gtk_init_check(&argc, &argv));
  GdkDisplay* gdk = gdk_display_get_default();
  assert(GDK_IS_X11_DISPLAY(gdk));
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_widget_realize(window);  // Keep the entire probe unmapped.
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkGLContext) context = gdk_window_create_gl_context(gtk_widget_get_window(window), &error);
  assert(context && gdk_gl_context_realize(context, &error));
  auto get_display = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(eglGetProcAddress("eglGetPlatformDisplayEXT"));
  assert(get_display);
  EGLDisplay egl_display = get_display(EGL_PLATFORM_X11_EXT, gdk_x11_display_get_xdisplay(gdk), nullptr);
  assert(eglInitialize(egl_display, nullptr, nullptr));
  const EGLint attributes[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT | EGL_OPENGL_BIT,
      EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE};
  EGLConfig config = nullptr; EGLint count = 0;
  assert(eglChooseConfig(egl_display, attributes, &config, 1, &count) && count);
  assert(eglBindAPI(EGL_OPENGL_ES_API));
  const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
  EGLContext engine_context = eglCreateContext(egl_display, config, EGL_NO_CONTEXT, context_attributes);
  assert(engine_context != EGL_NO_CONTEXT);
  RealizeBinding binding{egl_display, engine_context};
  assert(eglBindAPI(EGL_OPENGL_API));
  {
    mvd::X11GlBindingScope scope(gdk);
    Realize(window, &binding);
  }
  assert(binding.bound);
  assert(eglGetCurrentContext() == EGL_NO_CONTEXT);
  assert(eglQueryAPI() == EGL_OPENGL_API);
  assert(!gdk_gl_context_get_current() && !glXGetCurrentContext());
  g_print("No prior context: leaked EGL binding cleared, API restored.\n");
  gdk_gl_context_make_current(context);
  GLXContext glx = glXGetCurrentContext();
  Display* x11 = glXGetCurrentDisplay();
  GLXDrawable draw = glXGetCurrentDrawable(), read = glXGetCurrentReadDrawable();
  assert(glx);
  {
    mvd::X11GlBindingScope scope(gdk);
    assert(!gdk_gl_context_get_current() && !glXGetCurrentContext());
    Realize(window, &binding);
  }
  assert(gdk_gl_context_get_current() == context && glXGetCurrentContext() == glx);
  assert(glXGetCurrentDrawable() == draw && glXGetCurrentReadDrawable() == read);
  assert(eglGetCurrentContext() == EGL_NO_CONTEXT && eglQueryAPI() == EGL_OPENGL_API);
  g_print("GDK-owned GLX: native binding and GTK cache restored.\n");
  gdk_gl_context_clear_current();
  assert(glXMakeContextCurrent(x11, draw, read, glx));
  {
    mvd::X11GlBindingScope scope(gdk);
    Realize(window, &binding);
  }
  assert(!gdk_gl_context_get_current() && glXGetCurrentContext() == glx);
  assert(glXGetCurrentDrawable() == draw && glXGetCurrentReadDrawable() == read);
  assert(glXMakeContextCurrent(x11, None, None, nullptr));
  g_print("Raw GLX: exact draw/read binding restored without inventing GTK ownership.\n");
  assert(eglBindAPI(EGL_OPENGL_API));
  const EGLint desktop_attributes[] = {EGL_NONE};
  EGLContext desktop = eglCreateContext(egl_display, config, EGL_NO_CONTEXT, desktop_attributes);
  assert(desktop != EGL_NO_CONTEXT);
  const EGLint surface_attributes[] = {EGL_WIDTH, 2, EGL_HEIGHT, 2, EGL_NONE};
  EGLSurface draw_surface = eglCreatePbufferSurface(egl_display, config, surface_attributes);
  EGLSurface read_surface = eglCreatePbufferSurface(egl_display, config, surface_attributes);
  assert(draw_surface != EGL_NO_SURFACE && read_surface != EGL_NO_SURFACE);
  assert(eglMakeCurrent(egl_display, draw_surface, read_surface, desktop));
  {
    mvd::X11GlBindingScope inactive(nullptr);
    assert(eglGetCurrentContext() == desktop && eglQueryAPI() == EGL_OPENGL_API);
  }
  assert(eglGetCurrentContext() == desktop && eglGetCurrentDisplay() == egl_display);
  assert(eglGetCurrentSurface(EGL_DRAW) == draw_surface && eglGetCurrentSurface(EGL_READ) == read_surface);
  g_print("No display: scope leaves the existing native binding untouched.\n");
  {
    mvd::X11GlBindingScope scope(gdk);
    assert(eglGetCurrentContext() == EGL_NO_CONTEXT);
    Realize(window, &binding);
  }
  assert(eglQueryAPI() == EGL_OPENGL_API && eglGetCurrentContext() == desktop);
  assert(eglGetCurrentDisplay() == egl_display);
  assert(eglGetCurrentSurface(EGL_DRAW) == draw_surface && eglGetCurrentSurface(EGL_READ) == read_surface);
  assert(!gdk_gl_context_get_current());
  assert(eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT));
  eglDestroySurface(egl_display, draw_surface); eglDestroySurface(egl_display, read_surface);
  eglDestroyContext(egl_display, desktop);
  g_print("Raw EGL: exact API, display, context and draw/read surfaces restored.\n");

  // Final unref can run additional compositor cleanup after GtkWidget::destroy.
  // Keep both inside the same boundary, with another live GTK context restored.
  GtkWidget* victim = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_widget_realize(victim);
  g_object_ref(victim);  // Match the production deferred-destruction ownership.
  g_signal_connect(victim, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
    auto* state = static_cast<RealizeBinding*>(data); BindPlatform(state); ++state->cleanup_calls;
  }), &binding);
  g_object_set_data_full(G_OBJECT(victim), "platform-cleanup", &binding, +[](gpointer data) {
    auto* state = static_cast<RealizeBinding*>(data); BindPlatform(state); ++state->cleanup_calls;
  });
  assert(eglBindAPI(EGL_OPENGL_API));
  gdk_gl_context_make_current(context);
  {
    mvd::X11GlBindingScope scope(gdk);
    gtk_widget_destroy(victim);
    assert(binding.cleanup_calls == 1);
    g_object_unref(victim);
    assert(binding.cleanup_calls == 2);
  }
  assert(gdk_gl_context_get_current() == context && glXGetCurrentContext() == glx);
  assert(eglGetCurrentContext() == EGL_NO_CONTEXT && eglQueryAPI() == EGL_OPENGL_API);
  g_print("Destroy and final unref: cleanup succeeds and the other live GTK context is restored.\n");

  // The saved GdkGLContext can outlive the window being destroyed. Rebinding
  // that invalid drawable must not resurrect it in GDK's thread-local cache.
  gdk_gl_context_make_current(context);
  {
    mvd::X11GlBindingScope scope(gdk);
    gtk_widget_destroy(window);
  }
  assert(!gdk_gl_context_get_current() && !glXGetCurrentContext());
  assert(eglGetCurrentContext() == EGL_NO_CONTEXT);
  eglDestroyContext(egl_display, engine_context);
  g_print("Destroyed prior GTK drawable: bindings remain clear.\n");
}
