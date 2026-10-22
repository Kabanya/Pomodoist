#include "../x11_context.h"

#include <array>
#include <cassert>
#include <iostream>

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  GdkDisplay* gdk = gdk_display_get_default();
  assert(GDK_IS_X11_DISPLAY(gdk));
  Display* x11 = gdk_x11_display_get_xdisplay(gdk);
  const int attributes[] = {GLX_RENDER_TYPE, GLX_RGBA_BIT,
      GLX_DRAWABLE_TYPE, GLX_PBUFFER_BIT, None};
  int count = 0;
  GLXFBConfig* configs = glXChooseFBConfig(x11, DefaultScreen(x11), attributes, &count);
  assert(configs && count > 0);
  GLXContext previous = glXCreateNewContext(x11, configs[0], GLX_RGBA_TYPE, nullptr, True);
  const int pbuffer_attributes[] = {GLX_PBUFFER_WIDTH, 1, GLX_PBUFFER_HEIGHT, 1, None};
  GLXPbuffer pbuffer = glXCreatePbuffer(x11, configs[0], pbuffer_attributes);
  XFree(configs);
  assert(previous && pbuffer);
  assert(glXMakeContextCurrent(x11, pbuffer, pbuffer, previous));
  const EGLenum original_api = eglQueryAPI();

  pomodoist::X11UtilityContext utility{};
  assert(pomodoist::TryCreateX11UtilityContext(&utility));
  assert(glXGetCurrentContext() == previous);
  assert(eglQueryAPI() == original_api);

  GLuint producer = 0;
  EGLImageKHR image = EGL_NO_IMAGE_KHR;
  {
    pomodoist::NativeGlContextGuard restore(utility.display, utility.context);
    assert(eglMakeCurrent(utility.display, EGL_NO_SURFACE, EGL_NO_SURFACE, utility.context));
    const std::array<unsigned char, 4> expected{32, 64, 128, 255};
    glGenTextures(1, &producer);
    glBindTexture(GL_TEXTURE_2D, producer);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, expected.data());
    const EGLint image_attributes[] = {EGL_GL_TEXTURE_LEVEL_KHR, 0,
        EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE};
    image = eglCreateImageKHR(utility.display, utility.context, EGL_GL_TEXTURE_2D_KHR,
        reinterpret_cast<EGLClientBuffer>(static_cast<uintptr_t>(producer)), image_attributes);
    assert(image != EGL_NO_IMAGE_KHR);
    glFinish();
  }
  assert(glXGetCurrentContext() == previous);
  assert(glXGetCurrentDrawable() == pbuffer);
  assert(glXGetCurrentReadDrawable() == pbuffer);
  assert(eglQueryAPI() == original_api);

  EGLContext consumer = EGL_NO_CONTEXT;
  {
    const EGLenum saved_api = eglQueryAPI();
    eglBindAPI(EGL_OPENGL_ES_API);
    const EGLint config_attributes[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_NONE};
    EGLConfig config = nullptr;
    EGLint configs_found = 0;
    assert(eglChooseConfig(utility.display, config_attributes, &config, 1, &configs_found));
    assert(configs_found > 0);
    const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    // No shared context: this reproduces Flutter's independent render group.
    consumer = eglCreateContext(utility.display, config, EGL_NO_CONTEXT, context_attributes);
    eglBindAPI(saved_api);
    assert(consumer != EGL_NO_CONTEXT);
  }
  {
    pomodoist::NativeGlContextGuard restore(utility.display, consumer);
    assert(eglMakeCurrent(utility.display, EGL_NO_SURFACE, EGL_NO_SURFACE, consumer));
    GLuint imported = 0, framebuffer = 0;
    glGenTextures(1, &imported);
    glBindTexture(GL_TEXTURE_2D, imported);
    glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, image);
    assert(glGetError() == GL_NO_ERROR);
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, imported, 0);
    assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    std::array<unsigned char, 4> actual{};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, actual.data());
    std::cout << "RGBA readback: " << static_cast<int>(actual[0]) << "," << static_cast<int>(actual[1])
              << "," << static_cast<int>(actual[2]) << "," << static_cast<int>(actual[3]) << std::endl;
    assert((actual == std::array<unsigned char, 4>{32, 64, 128, 255}));
    glDeleteFramebuffers(1, &framebuffer);
    glDeleteTextures(1, &imported);
  }
  assert(glXGetCurrentContext() == previous);
  assert(eglQueryAPI() == original_api);
  // The guard must also restore an existing EGL/GLES binding (Wayland's case),
  // including its client API, after temporarily using the desktop GL utility.
  glXMakeContextCurrent(x11, None, None, nullptr);
  eglBindAPI(EGL_OPENGL_ES_API);
  assert(eglMakeCurrent(utility.display, EGL_NO_SURFACE, EGL_NO_SURFACE, consumer));
  {
    pomodoist::NativeGlContextGuard restore(utility.display, utility.context);
    assert(eglMakeCurrent(utility.display, EGL_NO_SURFACE, EGL_NO_SURFACE, utility.context));
  }
  assert(eglGetCurrentContext() == consumer);
  assert(eglGetCurrentDisplay() == utility.display);
  assert(eglQueryAPI() == EGL_OPENGL_ES_API);
  eglMakeCurrent(utility.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglBindAPI(original_api);
  assert(glXMakeContextCurrent(x11, pbuffer, pbuffer, previous));
  eglDestroyContext(utility.display, consumer);
  {
    pomodoist::NativeGlContextGuard restore(utility.display, utility.context);
    assert(eglMakeCurrent(utility.display, EGL_NO_SURFACE, EGL_NO_SURFACE, utility.context));
    eglDestroyImageKHR(utility.display, image);
    glDeleteTextures(1, &producer);
  }
  eglDestroyContext(utility.display, utility.context);
  glXMakeContextCurrent(x11, None, None, nullptr);
  glXDestroyPbuffer(x11, pbuffer);
  glXDestroyContext(x11, previous);
  std::cout << "X11 EGLImage -> unshared GLES GL_TEXTURE_2D RGBA readback and GLX restoration passed.\n";
}
