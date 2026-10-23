#ifndef MVD_LINUX_GL_BINDING_H_
#define MVD_LINUX_GL_BINDING_H_
#include <gtk/gtk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <epoxy/egl.h>
#include <epoxy/glx.h>
#endif

namespace mvd {
// Flutter 3.47's compositor-shader constructor and disposer bind raw EGL.
// GTK3 X11 paints with GLX and caches its own current GdkGLContext. Keep both
// APIs and that cache consistent across explicit view lifecycle boundaries.
class X11GlBindingScope {
 public:
  explicit X11GlBindingScope(GdkDisplay* display) {
#ifdef GDK_WINDOWING_X11
    if (!display || !GDK_IS_X11_DISPLAY(display)) return;
    active_ = true;
    gdk_context_ = gdk_gl_context_get_current();
    if (gdk_context_) g_object_ref(gdk_context_);
    egl_api_ = eglQueryAPI();
    egl_display_ = eglGetCurrentDisplay();
    egl_context_ = eglGetCurrentContext();
    egl_draw_ = eglGetCurrentSurface(EGL_DRAW);
    egl_read_ = eglGetCurrentSurface(EGL_READ);
    glx_context_ = glXGetCurrentContext();
    if (glx_context_) {
      glx_display_ = glXGetCurrentDisplay();
      glx_draw_ = glXGetCurrentDrawable();
      glx_read_ = glXGetCurrentReadDrawable();
    }
    Clear();
#else
    (void)display;
#endif
  }
  ~X11GlBindingScope() {
#ifdef GDK_WINDOWING_X11
    if (!active_) return;
    Clear();
    if (!eglBindAPI(egl_api_)) g_warning("Could not restore EGL client API after Flutter view lifecycle callback");
    if (gdk_context_) {
      // Destruction can invalidate the saved context's drawable while our ref
      // keeps the context object alive. Never repopulate GDK's cache with it.
      GdkWindow* window = gdk_gl_context_get_window(gdk_context_);
      if (window && !gdk_window_is_destroyed(window))
        gdk_gl_context_make_current(gdk_context_);
      g_object_unref(gdk_context_);
    } else if (egl_context_ != EGL_NO_CONTEXT) {
      if (!eglMakeCurrent(egl_display_, egl_draw_, egl_read_, egl_context_))
        g_warning("Could not restore EGL context after Flutter view lifecycle callback");
    } else if (glx_context_) {
      if (!glXMakeContextCurrent(glx_display_, glx_draw_, glx_read_, glx_context_))
        g_warning("Could not restore GLX context after Flutter view lifecycle callback");
    }
#endif
  }
  X11GlBindingScope(const X11GlBindingScope&) = delete;
  X11GlBindingScope& operator=(const X11GlBindingScope&) = delete;

 private:
#ifdef GDK_WINDOWING_X11
  static void Clear() {
    // Release an EGL context before asking GDK to unbind its cached GLX
    // context; the cache may already disagree with the raw native binding.
    EGLDisplay display = eglGetCurrentDisplay();
    if (display != EGL_NO_DISPLAY && eglGetCurrentContext() != EGL_NO_CONTEXT &&
        !eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT))
      g_warning("Could not clear EGL context around Flutter view lifecycle callback");
    gdk_gl_context_clear_current();
    GLXContext context = glXGetCurrentContext();
    if (context && !glXMakeContextCurrent(glXGetCurrentDisplay(), None, None, nullptr))
      g_warning("Could not clear GLX context around Flutter view lifecycle callback");
  }
  bool active_ = false;
  GdkGLContext* gdk_context_ = nullptr;
  EGLenum egl_api_ = EGL_OPENGL_ES_API;
  EGLDisplay egl_display_ = EGL_NO_DISPLAY;
  EGLContext egl_context_ = EGL_NO_CONTEXT;
  EGLSurface egl_draw_ = EGL_NO_SURFACE, egl_read_ = EGL_NO_SURFACE;
  Display* glx_display_ = nullptr;
  GLXContext glx_context_ = nullptr;
  GLXDrawable glx_draw_ = None, glx_read_ = None;
#endif
};
}  // namespace mvd
#endif  // MVD_LINUX_GL_BINDING_H_
