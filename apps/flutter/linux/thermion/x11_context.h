#ifndef POMODOIST_THERMION_X11_CONTEXT_H_
#define POMODOIST_THERMION_X11_CONTEXT_H_

#include <gtk/gtk.h>
#include <epoxy/egl.h>
#include <epoxy/gl.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <epoxy/glx.h>
#endif

namespace pomodoist {
// Thermion temporarily uses its utility context on GTK's thread. GTK may have
// left a GLX context current there, while Flutter's raster thread uses EGL.
// Release the native binding before switching APIs, and restore the exact EGL
// display/surfaces/API or GLX draw/read binding on every exit path.
class NativeGlContextGuard {
 public:
  NativeGlContextGuard(EGLDisplay target_display, EGLContext target_context)
      : target_display_(target_display), previous_api_(eglQueryAPI()),
        previous_display_(eglGetCurrentDisplay()), previous_context_(eglGetCurrentContext()),
        previous_draw_(eglGetCurrentSurface(EGL_DRAW)), previous_read_(eglGetCurrentSurface(EGL_READ)) {
#ifdef GDK_WINDOWING_X11
    GdkDisplay* display = gdk_display_get_default();
    if (display && GDK_IS_X11_DISPLAY(display)) {
      previous_glx_context_ = glXGetCurrentContext();
      if (previous_glx_context_) {
        previous_glx_display_ = glXGetCurrentDisplay();
        previous_glx_draw_ = glXGetCurrentDrawable();
        previous_glx_read_ = glXGetCurrentReadDrawable();
        glXMakeContextCurrent(previous_glx_display_, None, None, nullptr);
      }
    }
#endif
    if (previous_context_ != EGL_NO_CONTEXT)
      eglMakeCurrent(previous_display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    EGLint target_api = EGL_OPENGL_API;
    eglQueryContext(target_display, target_context, EGL_CONTEXT_CLIENT_TYPE, &target_api);
    eglBindAPI(target_api);
  }

  ~NativeGlContextGuard() {
    eglMakeCurrent(target_display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglBindAPI(previous_api_);
    if (previous_context_ != EGL_NO_CONTEXT)
      eglMakeCurrent(previous_display_, previous_draw_, previous_read_, previous_context_);
#ifdef GDK_WINDOWING_X11
    if (previous_glx_context_)
      glXMakeContextCurrent(previous_glx_display_, previous_glx_draw_, previous_glx_read_, previous_glx_context_);
#endif
  }
  NativeGlContextGuard(const NativeGlContextGuard&) = delete;
  NativeGlContextGuard& operator=(const NativeGlContextGuard&) = delete;

 private:
  EGLDisplay target_display_;
  EGLenum previous_api_;
  EGLDisplay previous_display_;
  EGLContext previous_context_;
  EGLSurface previous_draw_, previous_read_;
#ifdef GDK_WINDOWING_X11
  Display* previous_glx_display_ = nullptr;
  GLXContext previous_glx_context_ = nullptr;
  GLXDrawable previous_glx_draw_ = None, previous_glx_read_ = None;
#endif
};

struct X11UtilityContext {
  EGLDisplay display = EGL_NO_DISPLAY;
  EGLConfig config = nullptr;
  EGLContext context = EGL_NO_CONTEXT;
};

inline bool TryCreateX11UtilityContext(X11UtilityContext* result) {
#ifdef GDK_WINDOWING_X11
  GdkDisplay* gdk = gdk_display_get_default();
  if (!gdk || !GDK_IS_X11_DISPLAY(gdk)) return false;
  const auto get_platform_display = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
      eglGetProcAddress("eglGetPlatformDisplayEXT"));
  if (!get_platform_display) return false;
  // Native display identity must match Flutter/GDK. A GBM EGLDisplay cannot
  // export a texture-2D EGLImage for Flutter's X11 EGLDisplay on NVIDIA.
  EGLDisplay display = get_platform_display(EGL_PLATFORM_X11_EXT,
      gdk_x11_display_get_xdisplay(gdk), nullptr);
  if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr)) return false;
  if (!epoxy_has_egl_extension(display, "EGL_KHR_surfaceless_context") ||
      !epoxy_has_egl_extension(display, "EGL_KHR_image_base") ||
      !epoxy_has_egl_extension(display, "EGL_KHR_gl_texture_2D_image")) return false;
  const EGLenum previous_api = eglQueryAPI();
  if (!eglBindAPI(EGL_OPENGL_API)) return false;
  const EGLint config_attributes[] = {
      EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
  EGLConfig config = nullptr;
  EGLint count = 0;
  EGLContext context = EGL_NO_CONTEXT;
  if (eglChooseConfig(display, config_attributes, &config, 1, &count) && count > 0) {
    const EGLint context_attributes[] = {EGL_CONTEXT_MAJOR_VERSION, 4,
        EGL_CONTEXT_MINOR_VERSION, 1, EGL_NONE};
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
  }
  eglBindAPI(previous_api);
  if (context == EGL_NO_CONTEXT) return false;
  bool usable = false;
  {
    NativeGlContextGuard restore(display, context);
    usable = eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context);
  }
  if (!usable) {
    eglDestroyContext(display, context);
    return false;
  }
  *result = {display, config, context};
  // The plugin owns the utility context. The EGLDisplay belongs to GDK/Flutter:
  // never eglTerminate it when this context is destroyed.
  return true;
#else
  return false;
#endif
}
}  // namespace pomodoist
#endif  // POMODOIST_THERMION_X11_CONTEXT_H_
