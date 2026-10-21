#ifndef MVD_LINUX_WINDOW_H_
#define MVD_LINUX_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>

class MvdLinuxWindow {
 public:
  MvdLinuxWindow();
  ~MvdLinuxWindow();

  static std::mutex registry_mtx;
  static std::map<int64_t, std::shared_ptr<MvdLinuxWindow>> windows;

  int64_t view_id = -1;
  GtkWindow* window = nullptr;
  FlView* view = nullptr;

  bool is_prevent_close = false;
  bool is_confirm_close = false;
  bool is_pre_confirm = false;
  // Set while a gtk_window_close idle-callback is queued, cleared just before
  // the callback calls gtk_window_close so that a subsequent closeWindow call
  // (e.g. after on_delete returns TRUE) schedules a new callback correctly.
  bool close_pending = false;
  bool is_minimizable = true;
  bool is_maximizable = true;
  bool is_resizable = true;
  bool is_fullscreen = false;
  bool is_skip_taskbar = false;
  bool is_always_on_top = false;
  bool size_locked_by_non_resizable = false;
  GdkGeometry geometry_before_resize_lock{};
  GdkWindowHints hints_before_resize_lock = static_cast<GdkWindowHints>(0);
  bool has_geometry_before_resize_lock = false;
  bool window_button_visibility = true;
  bool is_ignore_mouse_events = false;
  bool is_forward_mouse_events = false;
  bool is_dialog = false;
  bool is_modal = false;
  int64_t dialog_parent_view_id = -1;
  int64_t modal_owner_view_id = -1;
  bool clamping_position = false;
  double opacity = 1.0;

  // Pending move: position requested before the window is first mapped.
  // Applied just before gtk_widget_show() so the WM receives the coordinates
  // in the X11 MapRequest (PPosition hint), preventing GTK_WIN_POS_CENTER
  // from overriding it.
  bool has_pending_move = false;
  gint pending_move_x = 0;
  gint pending_move_y = 0;

  GdkGeometry geometry{};
  GdkWindowHints hints = static_cast<GdkWindowHints>(0);
  // Last shadow delta measured in a non-maximized/non-fullscreen state.
  // Used to keep hints correct when ReapplyGeometryHints is called while the
  // window is maximized or fullscreen (where GTK hides the CSD shadow).
  gint cached_shadow_w = 0;
  gint cached_shadow_h = 0;
  // Header bar height stored during the last HIDE operation so the SHOW
  // direction can use it (gtk_widget_get_preferred_height of a hidden bar
  // returns 0 on some GTK versions).
  gint stored_hb_h = 0;
  GtkCssProvider* css_provider = nullptr;
  GtkCssProvider* csd_radius_provider = nullptr;
  gchar* title_bar_style = nullptr;
  GdkEventButton last_button{};

  gint last_configure_width = 0;
  gint last_configure_height = 0;
  gint last_configure_x = 0;
  gint last_configure_y = 0;
  bool has_configure_baseline = false;
  gint last_origin_x = 0;
  gint last_origin_y = 0;
  bool has_origin_baseline = false;
  bool is_dragging = false;
  bool is_resizing = false;
  guint drag_release_watch_id = 0;
  std::function<void(const char*)> event_emitter_;

  void SetEventEmitter(std::function<void(const char*)> emitter);
  void SeedConfigureBaseline();
  void HandleConfigureEvent(const GdkEventConfigure* configure);
  void HandleWindowStateEvent(GdkEventWindowState* event);
  void EmitShow();
  void EmitHide();
  bool IsPointerButtonStillPressed() const;
  void EnsureDragReleaseWatcher();
  void StopDragReleaseWatcher();
  void FinishInteractiveGesture();
  void PollOriginMove();

  void SetAsFrameless();
  void Close();
  /// Force destroy, skips soft-close.
  void Destroy();
  void Focus();
  bool IsFocused();
  void Show();
  void Hide();
  bool IsVisible();
  bool IsMaximized();
  void Maximize();
  void Unmaximize();
  bool IsMinimized();
  void Minimize();
  void Restore();
  bool IsFullScreen();
  void SetFullScreen(bool fs);
  void SetAspectRatio(float ar);
  bool SetBackgroundColor(int r, int g, int b, int a);
  FlValue* GetBounds();
  void SetBounds(FlValue* args);
  void SetSize(double width, double height);
  void SetPosition(double x, double y);
  void ApplyPendingMove();
  void Center();
  void SetMinimumSize(float w, float h);
  void SetMaximumSize(float w, float h);
  void RefreshShadowCache();
  void ReapplyGeometryHints();
  void ClampWindowToConstraints();
  bool IsResizable();
  void SetResizable(bool v);
  bool IsMinimizable();
  void SetMinimizable(bool v);
  bool IsMaximizable();
  void SetMaximizable(bool v);
  bool IsClosable();
  void SetClosable(bool v);
  bool IsAlwaysOnTop();
  void SetAlwaysOnTop(bool v);
  const gchar* GetTitle();
  void SetTitle(const gchar* t);
  void SetTitleBarStyle(const gchar* style, bool window_button_visibility);
  FlValue* GetTitleBarStyle();
  bool IsSkipTaskbar();
  void SetSkipTaskbar(bool v);
  double GetOpacity();
  void SetOpacity(double o);
  void SetBrightness(const gchar* brightness);
  void PopUpWindowMenu();
  void StartDragging();
  void StartResizing(const gchar* edge);
  bool IsMovable();
  void SetMovable(bool v);
  bool HasShadow();
  void SetHasShadow(bool v);
  void SetIgnoreMouseEvents(bool ignore, bool forward);
  std::pair<bool, bool> IsIgnoreMouseEvents();

  void ApplyWindowTypeHint();

  static std::shared_ptr<MvdLinuxWindow> Find(int64_t view_id);
  static void Unregister(int64_t view_id);
  static void DecorateToplevel(GtkWindow* window, const char* title);
  static void CenterOnParent(GtkWindow* dialog, GtkWindow* parent, int width,
                             int height);
  void CenterOnDialogParent();
  void ClampToParentBounds();
  /// Parent-only modal input block (like Windows EnableWindow).
  static void UpdateModalStateLayer(int64_t owner_view_id);
  static int64_t GetActiveModalFocusTarget(int64_t owner_view_id);
  static void FocusModalTarget(int64_t view_id);
  static GdkWindow* GetGdkWindow(GtkWindow* w);
  static GtkWidget* HeaderBarOf(GtkWindow* w);
  static FlValue* MakeBounds(GtkWindow* w);

  static gboolean DragReleaseWatchCb(gpointer data);
};

#endif  // MVD_LINUX_WINDOW_H_
