#include "mvd_linux_window.h"
#include "mvd_linux_internal.h"
#include <gtk-layer-shell.h>
#include "mvd_linux_log.h"
#include <gtk/gtk.h>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstring>
#include <vector>

#define MVD_LOG MVD_LOG_WINDOW

// Returns X11 XID as a string for debug logs (X11 sessions only).
static std::string mvd_xid_str(GtkWindow* w) {
#ifdef GDK_WINDOWING_X11
  if (!w) return "(null-gtk-window)";
  GdkWindow* gdk = gtk_widget_get_window(GTK_WIDGET(w));
  if (!gdk) return "(not-realized)";
  if (GDK_IS_X11_WINDOW(gdk)) {
    char buf[32];
    snprintf(buf, sizeof(buf), "XID=0x%lx", GDK_WINDOW_XID(gdk));
    return buf;
  }
  return "(wayland-surface)";
#else
  (void)w;
  return "(no-x11-support)";
#endif
}

std::mutex MvdLinuxWindow::registry_mtx;
std::map<int64_t, std::shared_ptr<MvdLinuxWindow>> MvdLinuxWindow::windows;

MvdLinuxWindow::MvdLinuxWindow() {
  geometry.min_width = -1;
  geometry.min_height = -1;
  geometry.max_width = G_MAXINT;
  geometry.max_height = G_MAXINT;
  MVD_LOG("MvdLinuxWindow::ctor  this=%p", static_cast<void*>(this));
}

MvdLinuxWindow::~MvdLinuxWindow() {
  MVD_LOG("MvdLinuxWindow::dtor  this=%p  view_id=%" G_GINT64_FORMAT
          "  window=%p  view=%p  is_dialog=%d  is_modal=%d",
          static_cast<void*>(this), view_id,
          static_cast<void*>(window), static_cast<void*>(view),
          static_cast<int>(is_dialog), static_cast<int>(is_modal));
  MVD_LOG("MvdLinuxWindow::dtor  css_provider=%p  csd_radius_provider=%p"
          "  title_bar_style='%s'",
          static_cast<void*>(css_provider),
          static_cast<void*>(csd_radius_provider),
          title_bar_style ? title_bar_style : "(null)");
  if (css_provider) {
    MVD_LOG("MvdLinuxWindow::dtor  unref css_provider=%p",
            static_cast<void*>(css_provider));
    g_object_unref(css_provider);
  }
  if (csd_radius_provider) {
    MVD_LOG("MvdLinuxWindow::dtor  unref csd_radius_provider=%p",
            static_cast<void*>(csd_radius_provider));
    g_object_unref(csd_radius_provider);
  }
  if (title_bar_style) {
    MVD_LOG("MvdLinuxWindow::dtor  g_free title_bar_style='%s'",
            title_bar_style);
    g_free(title_bar_style);
  }
  MVD_LOG("MvdLinuxWindow::dtor  DONE  this=%p", static_cast<void*>(this));
  StopDragReleaseWatcher();
}

void MvdLinuxWindow::SetEventEmitter(std::function<void(const char*)> emitter) {
  event_emitter_ = std::move(emitter);
}

void MvdLinuxWindow::SeedConfigureBaseline() {
  if (!window) {
    return;
  }
  gtk_window_get_position(window, &last_configure_x, &last_configure_y);
  gtk_window_get_size(window, &last_configure_width, &last_configure_height);
  has_configure_baseline = true;
  has_origin_baseline = false;
}

void MvdLinuxWindow::HandleConfigureEvent(const GdkEventConfigure* configure) {
  if (!configure || !event_emitter_) {
    return;
  }
  if (!has_configure_baseline) {
    last_configure_x = configure->x;
    last_configure_y = configure->y;
    last_configure_width = configure->width;
    last_configure_height = configure->height;
    has_configure_baseline = true;
    return;
  }

  const bool size_changed =
      configure->width != last_configure_width ||
      configure->height != last_configure_height;
  const bool pos_changed = configure->x != last_configure_x ||
                           configure->y != last_configure_y;

  if (IsPointerButtonStillPressed()) {
    if (size_changed) {
      is_resizing = true;
    } else if (pos_changed) {
      is_dragging = true;
    }
    if (is_dragging || is_resizing) {
      EnsureDragReleaseWatcher();
    }
  }

  if (size_changed) {
    last_configure_width = configure->width;
    last_configure_height = configure->height;
    event_emitter_("resize");
  } else if (pos_changed) {
    last_configure_x = configure->x;
    last_configure_y = configure->y;
    event_emitter_("move");
  }
}

namespace {

gboolean enforce_unmaximize_cb(gpointer data) {
  auto* win = static_cast<GtkWindow*>(data);
  if (win && GTK_IS_WINDOW(win)) {
    gtk_window_unmaximize(win);
  }
  return G_SOURCE_REMOVE;
}

gboolean enforce_deiconify_cb(gpointer data) {
  auto* win = static_cast<GtkWindow*>(data);
  if (win && GTK_IS_WINDOW(win)) {
    gtk_window_deiconify(win);
  }
  return G_SOURCE_REMOVE;
}

}  // namespace

void MvdLinuxWindow::HandleWindowStateEvent(GdkEventWindowState* event) {
  if (!event || !window) {
    return;
  }

  if (event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) {
    is_fullscreen =
        (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
    if (event_emitter_) {
      event_emitter_(is_fullscreen ? "enter-full-screen" : "leave-full-screen");
    }
  }

  if (event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) {
    if (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) {
      if (!is_maximizable) {
        g_idle_add(enforce_unmaximize_cb, window);
      } else if (event_emitter_) {
        event_emitter_("maximize");
      }
    } else if (event_emitter_) {
      event_emitter_("unmaximize");
    }
  }

  if (event->changed_mask & GDK_WINDOW_STATE_ICONIFIED) {
    if (event->new_window_state & GDK_WINDOW_STATE_ICONIFIED) {
      if (!is_minimizable) {
        g_idle_add(enforce_deiconify_cb, window);
      } else if (event_emitter_) {
        event_emitter_("minimize");
      }
    } else if (event_emitter_) {
      event_emitter_("restore");
    }
  }

  const GdkWindowState left = static_cast<GdkWindowState>(
      event->changed_mask & ~event->new_window_state);
  const bool left_max_or_fs =
      (left & GDK_WINDOW_STATE_MAXIMIZED) ||
      (left & GDK_WINDOW_STATE_FULLSCREEN);
  if (left_max_or_fs) {
    ReapplyGeometryHints();
  }
}

void MvdLinuxWindow::EmitShow() {
  if (event_emitter_) {
    event_emitter_("show");
  }
}

void MvdLinuxWindow::EmitHide() {
  if (event_emitter_) {
    event_emitter_("hide");
  }
}

bool MvdLinuxWindow::IsPointerButtonStillPressed() const {
  if (!window) {
    return false;
  }
  auto* screen = gtk_window_get_screen(window);
  auto* display = gdk_screen_get_display(screen);
  auto* seat = gdk_display_get_default_seat(display);
  auto* device = gdk_seat_get_pointer(seat);
  GdkWindow* gdk = gtk_widget_get_window(GTK_WIDGET(window));
  if (!gdk || !device) {
    return false;
  }

  gint x = 0;
  gint y = 0;
  GdkModifierType state = static_cast<GdkModifierType>(0);
  gdk_window_get_device_position(gdk, device, &x, &y, &state);
  const guint pressed_button =
      last_button.button ? last_button.button : GDK_BUTTON_PRIMARY;
  GdkModifierType button_mask = GDK_BUTTON1_MASK;
  if (pressed_button == 2) {
    button_mask = GDK_BUTTON2_MASK;
  } else if (pressed_button == 3) {
    button_mask = GDK_BUTTON3_MASK;
  }
  return (state & button_mask) != 0;
}

void MvdLinuxWindow::StopDragReleaseWatcher() {
  if (drag_release_watch_id == 0) {
    return;
  }
  const guint tag = drag_release_watch_id;
  drag_release_watch_id = 0;
  g_source_remove(tag);
}

void MvdLinuxWindow::FinishInteractiveGesture() {
  if (!is_dragging && !is_resizing) {
    return;
  }
  if (IsPointerButtonStillPressed()) {
    return;
  }
  if (is_dragging && event_emitter_) {
    event_emitter_("moved");
  }
  if (is_resizing && event_emitter_) {
    event_emitter_("resized");
  }
  is_dragging = false;
  is_resizing = false;
  has_origin_baseline = false;
}

void MvdLinuxWindow::PollOriginMove() {
  if (!window || !event_emitter_) {
    return;
  }
  GdkWindow* gdk = gtk_widget_get_window(GTK_WIDGET(window));
  if (!gdk) {
    return;
  }
  gint ox = 0;
  gint oy = 0;
  gdk_window_get_origin(gdk, &ox, &oy);
  if (!has_origin_baseline) {
    last_origin_x = ox;
    last_origin_y = oy;
    has_origin_baseline = true;
    return;
  }
  if (ox == last_origin_x && oy == last_origin_y) {
    return;
  }
  last_origin_x = ox;
  last_origin_y = oy;
  if (!is_dragging && !is_resizing) {
    is_dragging = true;
    EnsureDragReleaseWatcher();
  }
  event_emitter_("move");
}

void MvdLinuxWindow::EnsureDragReleaseWatcher() {
  StopDragReleaseWatcher();
  drag_release_watch_id = g_idle_add(DragReleaseWatchCb, this);
}

gboolean MvdLinuxWindow::DragReleaseWatchCb(gpointer data) {
  auto* self = static_cast<MvdLinuxWindow*>(data);
  std::shared_ptr<MvdLinuxWindow> keep;
  {
    std::lock_guard<std::mutex> lock(registry_mtx);
    auto it = windows.find(self->view_id);
    if (it == windows.end()) {
      self->drag_release_watch_id = 0;
      return G_SOURCE_REMOVE;
    }
    keep = it->second;
  }
  if (!keep->window) {
    keep->drag_release_watch_id = 0;
    return G_SOURCE_REMOVE;
  }

  if (keep->IsPointerButtonStillPressed()) {
    keep->PollOriginMove();
    return G_SOURCE_CONTINUE;
  }

  keep->FinishInteractiveGesture();
  keep->drag_release_watch_id = 0;
  return G_SOURCE_REMOVE;
}

GdkWindow* MvdLinuxWindow::GetGdkWindow(GtkWindow* w) {
  if (!w) {
    return nullptr;
  }
  return gtk_widget_get_window(GTK_WIDGET(w));
}

GtkWidget* MvdLinuxWindow::HeaderBarOf(GtkWindow* w) {
  GtkWidget* titlebar = gtk_window_get_titlebar(w);
  if (titlebar &&
      (GTK_IS_HEADER_BAR(titlebar) ||
       g_str_has_suffix(G_OBJECT_TYPE_NAME(titlebar), "HeaderBar"))) {
    return titlebar;
  }
  return nullptr;
}

FlValue* MvdLinuxWindow::MakeBounds(GtkWindow* w) {
  gint x = 0;
  gint y = 0;
  gint width = 0;
  gint height = 0;
  gtk_window_get_position(w, &x, &y);
  gtk_window_get_size(w, &width, &height);
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "x", fl_value_new_float(x));
  fl_value_set_string_take(map, "y", fl_value_new_float(y));
  fl_value_set_string_take(map, "width", fl_value_new_float(width));
  fl_value_set_string_take(map, "height", fl_value_new_float(height));
  return map;
}

std::shared_ptr<MvdLinuxWindow> MvdLinuxWindow::Find(int64_t view_id) {
  std::lock_guard<std::mutex> lock(registry_mtx);
  auto it = windows.find(view_id);
  return it == windows.end() ? nullptr : it->second;
}

void MvdLinuxWindow::Unregister(int64_t view_id) {
  std::lock_guard<std::mutex> lock(registry_mtx);
  const size_t before = windows.size();
  windows.erase(view_id);
  const size_t after = windows.size();
  MVD_LOG("Unregister  view_id=%" G_GINT64_FORMAT
          "  windows: %zu -> %zu",
          view_id, before, after);
}

void MvdLinuxWindow::SetAsFrameless() {
  if (!window) {
    return;
  }
  // Hide the header bar when using client-side decorations.
  GtkWidget* hb = HeaderBarOf(window);
  if (hb) {
    gtk_widget_set_visible(hb, FALSE);
  }
  gtk_window_set_decorated(window, FALSE);
  ReapplyGeometryHints();
}

void MvdLinuxWindow::Close() {
  MVD_LOG("Close  view_id=%" G_GINT64_FORMAT "  window=%p  %s",
          view_id, static_cast<void*>(window), mvd_xid_str(window).c_str());
  if (!window) {
    MVD_LOG("Close  view_id=%" G_GINT64_FORMAT "  SKIP: window is null",
            view_id);
    return;
  }
  // Guard against duplicate idle callbacks when the caller invokes Close()
  // multiple times before the first gtk_window_close fires (e.g. the Dart
  // side calling closeWindow() several times in quick succession).
  // The flag is cleared by the idle callback just before it calls
  // gtk_window_close, so if on_delete returns TRUE (blocking the close) a
  // subsequent Call to Close() will queue a new callback correctly.
  if (close_pending) {
    MVD_LOG("Close  view_id=%" G_GINT64_FORMAT
            "  SKIP: gtk_window_close already queued", view_id);
    return;
  }
  close_pending = true;
  MVD_LOG("Close  view_id=%" G_GINT64_FORMAT
          "  scheduling gtk_window_close via g_idle_add", view_id);
  auto* vid = new int64_t(view_id);
  g_idle_add(
      [](gpointer data) -> gboolean {
        std::unique_ptr<int64_t> p(static_cast<int64_t*>(data));
        const int64_t vid = *p;
        MVD_LOG("Close  idle_cb  view_id=%" G_GINT64_FORMAT
                "  looking up window in registry", vid);
        auto wm = MvdLinuxWindow::Find(vid);
        if (wm && wm->window) {
          // Reset before gtk_window_close so that a new Close() call works
          // correctly if on_delete returns TRUE (blocking the current close).
          wm->close_pending = false;
          MVD_LOG("Close  idle_cb  view_id=%" G_GINT64_FORMAT
                  "  calling gtk_window_close on window=%p  %s",
                  vid, static_cast<void*>(wm->window),
                  mvd_xid_str(wm->window).c_str());
          gtk_window_close(wm->window);
          MVD_LOG("Close  idle_cb  view_id=%" G_GINT64_FORMAT
                  "  gtk_window_close returned", vid);
        } else {
          MVD_LOG("Close  idle_cb  view_id=%" G_GINT64_FORMAT
                  "  SKIP: wm=%p or window already null",
                  vid, static_cast<void*>(wm.get()));
        }
        return G_SOURCE_REMOVE;
      },
      vid);
  MVD_LOG("Close  view_id=%" G_GINT64_FORMAT "  g_idle_add done", view_id);
}

void MvdLinuxWindow::Destroy() {
  MVD_LOG("Destroy  START  view_id=%" G_GINT64_FORMAT
          "  window=%p  view=%p  is_modal=%d  modal_owner=%" G_GINT64_FORMAT
          "  is_dialog=%d  %s",
          view_id, static_cast<void*>(window), static_cast<void*>(view),
          static_cast<int>(is_modal), modal_owner_view_id,
          static_cast<int>(is_dialog), mvd_xid_str(window).c_str());
  if (!window) {
    MVD_LOG("Destroy  SKIP: window already null  view_id=%" G_GINT64_FORMAT,
            view_id);
    return;
  }
  StopDragReleaseWatcher();
  const bool was_modal = is_modal;
  const int64_t owner_id = modal_owner_view_id;
  const int64_t vid = view_id;
  GtkWindow* w = window;
  MVD_LOG("Destroy  nulling this->window and this->view  view_id=%"
          G_GINT64_FORMAT "  w=%p  view=%p",
          view_id, static_cast<void*>(w), static_cast<void*>(view));
  window = nullptr;
  view = nullptr;
  MVD_LOG("Destroy  calling Unregister(%" G_GINT64_FORMAT ")  w=%p",
          vid, static_cast<void*>(w));
  Unregister(vid);

  // Update modal state immediately so the owner regains input before the
  // GTK widget is gone.
  if (was_modal && owner_id >= 0) {
    MVD_LOG("Destroy  was_modal=true, updating modal layer for owner=%"
            G_GINT64_FORMAT, owner_id);
    UpdateModalStateLayer(owner_id);
    MVD_LOG("Destroy  focusing modal target for owner=%" G_GINT64_FORMAT,
            owner_id);
    FocusModalTarget(GetActiveModalFocusTarget(owner_id));
  }

  // ---- Deferred destroy (same rationale as on_delete FINAL CLOSE) ----------
  //
  // Calling gtk_widget_destroy while Flutter's raster thread still has frames
  // queued for this view causes fl_compositor / FlView to be accessed after
  // the GObject has been disposed, producing GLib-GObject-CRITICAL warnings
  // and risking GLX context corruption.
  //
  // Fix: hide the window immediately (visual feedback), then destroy it 100 ms
  // later.  By that time Dart has received the 'destroyWindow' acknowledgment,
  // removed the view from its widget tree, and Flutter's raster thread has
  // drained any in-flight frames for this view.
  // --------------------------------------------------------------------------
  MVD_LOG("Destroy  hiding window immediately  view_id=%" G_GINT64_FORMAT
          "  w=%p", vid, static_cast<void*>(w));
  gtk_widget_hide(GTK_WIDGET(w));

  // Keep the GObject alive across the timer.
  g_object_ref(GTK_WIDGET(w));

  struct DestroyCtx { GtkWidget* widget; int64_t vid; };
  auto* ctx = new DestroyCtx{GTK_WIDGET(w), vid};

  MVD_LOG("Destroy  scheduling deferred gtk_widget_destroy (100 ms)"
          "  view_id=%" G_GINT64_FORMAT "  w=%p", vid, static_cast<void*>(w));

  g_timeout_add(
      100,
      [](gpointer data) -> gboolean {
        auto* c = static_cast<DestroyCtx*>(data);
        MVD_LOG("Destroy  deferred_destroy_cb  view_id=%" G_GINT64_FORMAT
                "  calling gtk_widget_destroy  widget=%p",
                c->vid, static_cast<void*>(c->widget));
        gtk_widget_destroy(c->widget);
        MVD_LOG("Destroy  deferred_destroy_cb  view_id=%" G_GINT64_FORMAT
                "  gtk_widget_destroy returned  releasing extra GObject ref",
                c->vid);
        g_object_unref(c->widget);
        delete c;
        return G_SOURCE_REMOVE;
      },
      ctx);

  MVD_LOG("Destroy  END (deferred)  original view_id=%" G_GINT64_FORMAT, vid);
}

namespace {

std::vector<int64_t> GetOwnedModalViewIds(int64_t owner_view_id) {
  std::vector<int64_t> owned;
  std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
  for (const auto& entry : MvdLinuxWindow::windows) {
    const auto& wm = entry.second;
    if (wm->is_modal && wm->modal_owner_view_id == owner_view_id) {
      owned.push_back(entry.first);
    }
  }
  return owned;
}

void SetWindowInputEnabled(GtkWindow* window, bool enabled) {
  if (!window) {
    return;
  }
  gtk_widget_set_sensitive(GTK_WIDGET(window), enabled ? TRUE : FALSE);
}

void DisableModalSubtree(int64_t view_id) {
  auto wm = MvdLinuxWindow::Find(view_id);
  if (!wm || !wm->window) {
    return;
  }
  SetWindowInputEnabled(wm->window, false);
  for (int64_t child_id : GetOwnedModalViewIds(view_id)) {
    DisableModalSubtree(child_id);
  }
}

}  // namespace

void MvdLinuxWindow::UpdateModalStateLayer(int64_t owner_view_id) {
  auto owner = Find(owner_view_id);
  if (!owner || !owner->window) {
    return;
  }

  const std::vector<int64_t> owned = GetOwnedModalViewIds(owner_view_id);
  if (owned.empty()) {
    SetWindowInputEnabled(owner->window, true);
    return;
  }

  SetWindowInputEnabled(owner->window, false);

  int64_t latest_view_id = owned.front();
  for (int64_t child_id : owned) {
    if (child_id > latest_view_id) {
      latest_view_id = child_id;
    }
  }

  for (int64_t child_id : owned) {
    auto child = Find(child_id);
    if (!child || !child->window) {
      continue;
    }
    if (child_id == latest_view_id) {
      UpdateModalStateLayer(child_id);
      SetWindowInputEnabled(child->window, true);
    } else {
      DisableModalSubtree(child_id);
    }
  }
}

int64_t MvdLinuxWindow::GetActiveModalFocusTarget(int64_t owner_view_id) {
  auto owner = Find(owner_view_id);
  if (!owner || !owner->window) {
    return -1;
  }

  const std::vector<int64_t> owned = GetOwnedModalViewIds(owner_view_id);
  if (owned.empty()) {
    return owner_view_id;
  }

  int64_t latest_view_id = owned.front();
  for (int64_t child_id : owned) {
    if (child_id > latest_view_id) {
      latest_view_id = child_id;
    }
  }
  return GetActiveModalFocusTarget(latest_view_id);
}

void MvdLinuxWindow::FocusModalTarget(int64_t view_id) {
  if (view_id < 0) {
    return;
  }
  auto wm = Find(view_id);
  if (wm) {
    wm->Focus();
  }
}

void MvdLinuxWindow::DecorateToplevel(GtkWindow* window, const char* title) {
  if (!window) {
    return;
  }
  const char* resolved_title = (title && title[0]) ? title : "Flutter";
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, resolved_title);
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, resolved_title);
  }
}

void MvdLinuxWindow::CenterOnParent(GtkWindow* dialog, GtkWindow* parent,
                                    int width, int height) {
  if (!dialog || !parent) {
    return;
  }
  gint px = 0;
  gint py = 0;
  gint pw = 0;
  gint ph = 0;
  gtk_window_get_position(parent, &px, &py);
  gtk_window_get_size(parent, &pw, &ph);

  gint dw = width;
  gint dh = height;
  if (gtk_widget_get_realized(GTK_WIDGET(dialog))) {
    gtk_window_get_size(dialog, &dw, &dh);
  }

  gtk_window_move(dialog, px + (pw - dw) / 2, py + (ph - dh) / 2);
}

void MvdLinuxWindow::CenterOnDialogParent() {
  if (dialog_parent_view_id < 0 || !window) {
    return;
  }
  auto parent = Find(dialog_parent_view_id);
  if (!parent || !parent->window) {
    return;
  }
  gint dw = 0;
  gint dh = 0;
  gtk_window_get_size(window, &dw, &dh);
  CenterOnParent(window, parent->window, dw, dh);
}

void MvdLinuxWindow::ClampToParentBounds() {
  if (!is_modal || dialog_parent_view_id < 0 || !window || clamping_position) {
    return;
  }
  auto parent = Find(dialog_parent_view_id);
  if (!parent || !parent->window) {
    return;
  }

  gint px = 0;
  gint py = 0;
  gint pw = 0;
  gint ph = 0;
  gtk_window_get_position(parent->window, &px, &py);
  gtk_window_get_size(parent->window, &pw, &ph);

  gint dx = 0;
  gint dy = 0;
  gint dw = 0;
  gint dh = 0;
  gtk_window_get_position(window, &dx, &dy);
  gtk_window_get_size(window, &dw, &dh);

  const gint min_x = px;
  const gint min_y = py;
  gint max_x = px + pw - dw;
  gint max_y = py + ph - dh;
  if (max_x < min_x) {
    max_x = min_x;
  }
  if (max_y < min_y) {
    max_y = min_y;
  }

  gint cx = dx;
  gint cy = dy;
  if (dx < min_x) {
    cx = min_x;
  }
  if (dy < min_y) {
    cy = min_y;
  }
  if (dx > max_x) {
    cx = max_x;
  }
  if (dy > max_y) {
    cy = max_y;
  }

  if (cx == dx && cy == dy) {
    return;
  }

  clamping_position = true;
  gtk_window_move(window, cx, cy);
  clamping_position = false;
}

void MvdLinuxWindow::Focus() {
  MVD_LOG("Focus  view_id=%" G_GINT64_FORMAT "  window=%p",
          view_id, static_cast<void*>(window));
  if (window) {
    gtk_window_present(window);
  }
}

bool MvdLinuxWindow::IsFocused() {
  return window ? gtk_window_is_active(window) : false;
}

void MvdLinuxWindow::Show() {
  MVD_LOG("Show  view_id=%" G_GINT64_FORMAT
          "  window=%p  is_dialog=%d  is_modal=%d  parent_id=%" G_GINT64_FORMAT,
          view_id, static_cast<void*>(window),
          static_cast<int>(is_dialog), static_cast<int>(is_modal),
          dialog_parent_view_id);
  if (!window) {
    MVD_LOG("Show  SKIP: window is null  view_id=%" G_GINT64_FORMAT, view_id);
    return;
  }
  if (is_dialog && dialog_parent_view_id >= 0) {
    MVD_LOG("Show  centering dialog on parent_id=%" G_GINT64_FORMAT,
            dialog_parent_view_id);
    CenterOnDialogParent();
    if (is_modal) {
      ClampToParentBounds();
    }
  }
  // Apply any position set before the window was mapped so the WM receives
  // the coordinates in the X11 MapRequest (PPosition hint).
  ApplyPendingMove();
  gtk_widget_show(GTK_WIDGET(window));
  if (focus_on_show) gtk_window_present(window);
  SeedConfigureBaseline();
  MVD_LOG("Show  DONE  view_id=%" G_GINT64_FORMAT, view_id);
}

void MvdLinuxWindow::Hide() {
  MVD_LOG("Hide  view_id=%" G_GINT64_FORMAT "  window=%p",
          view_id, static_cast<void*>(window));
  if (!window) {
    MVD_LOG("Hide  SKIP: window is null  view_id=%" G_GINT64_FORMAT, view_id);
    return;
  }
  gint x = 0;
  gint y = 0;
  gint w = 0;
  gint h = 0;
  gtk_window_get_position(window, &x, &y);
  gtk_window_get_size(window, &w, &h);
  MVD_LOG("Hide  current bounds: pos=(%d,%d) size=%dx%d  view_id=%"
          G_GINT64_FORMAT, x, y, w, h, view_id);
  gtk_widget_hide(GTK_WIDGET(window));
  if (gtk_layer_is_layer_window(window)) return;
  gtk_window_move(window, x, y);
  gtk_window_resize(window, w, h);
  MVD_LOG("Hide  DONE  view_id=%" G_GINT64_FORMAT, view_id);
}

bool MvdLinuxWindow::IsVisible() {
  return window ? gtk_widget_is_visible(GTK_WIDGET(window)) : false;
}

bool MvdLinuxWindow::IsMaximized() {
  return window ? gtk_window_is_maximized(window) : false;
}

void MvdLinuxWindow::Maximize() {
  if (window) {
    gtk_window_maximize(window);
  }
}

void MvdLinuxWindow::Unmaximize() {
  if (window) {
    gtk_window_unmaximize(window);
  }
}

bool MvdLinuxWindow::IsMinimized() {
  if (!window) {
    return false;
  }
  auto* gdk = GetGdkWindow(window);
  return gdk ? (gdk_window_get_state(gdk) & GDK_WINDOW_STATE_ICONIFIED) != 0
             : false;
}

void MvdLinuxWindow::Minimize() {
  if (window) {
    gtk_window_iconify(window);
  }
}

void MvdLinuxWindow::Restore() {
  if (!window) {
    return;
  }
  gtk_window_deiconify(window);
  gtk_window_present(window);
}

bool MvdLinuxWindow::IsFullScreen() {
  if (!window) {
    return false;
  }
  auto* gdk = GetGdkWindow(window);
  return gdk ? (gdk_window_get_state(gdk) & GDK_WINDOW_STATE_FULLSCREEN) != 0
             : false;
}

void MvdLinuxWindow::SetFullScreen(bool fs) {
  if (!window) {
    return;
  }
  is_fullscreen = fs;
  if (fs) {
    gtk_window_fullscreen(window);
  } else {
    gtk_window_unfullscreen(window);
  }
}

void MvdLinuxWindow::SetAspectRatio(float ar) {
  if (!window) {
    return;
  }
  geometry.min_aspect = ar;
  geometry.max_aspect = ar;
  if (ar >= 0) {
    hints = static_cast<GdkWindowHints>(hints | GDK_HINT_ASPECT);
  } else {
    hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_ASPECT);
  }
  ReapplyGeometryHints();
}

bool MvdLinuxWindow::SetBackgroundColor(int r, int g, int b, int a) {
  if (!window) {
    return false;
  }
  GdkRGBA rgba;
  rgba.red = r / 255.0;
  rgba.green = g / 255.0;
  rgba.blue = b / 255.0;
  rgba.alpha = a / 255.0;
  if (view) fl_view_set_background_color(view, &rgba);
  g_autofree gchar* color = gdk_rgba_to_string(&rgba);
  g_autofree gchar* css =
      g_strdup_printf("window { background-color: %s; }", color);
  if (!css_provider) {
    css_provider = gtk_css_provider_new();
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(GTK_WIDGET(window)),
        GTK_STYLE_PROVIDER(css_provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  }
  g_autoptr(GError) error = nullptr;
  gtk_css_provider_load_from_data(css_provider, css, -1, &error);
  return error == nullptr;
}

FlValue* MvdLinuxWindow::GetBounds() {
  if (!window) {
    return nullptr;
  }
  if (gtk_layer_is_layer_window(window)) return mvd_linux_layer_bounds(window);
  return MakeBounds(window);
}

void MvdLinuxWindow::SetBounds(FlValue* args) {
  if (!window || !args) {
    return;
  }
  FlValue* x = fl_value_lookup_string(args, "x");
  FlValue* y = fl_value_lookup_string(args, "y");
  if (x && y) {
    SetPosition(fl_value_get_float(x), fl_value_get_float(y));
  }
  FlValue* w = fl_value_lookup_string(args, "width");
  FlValue* h = fl_value_lookup_string(args, "height");
  if (w && h) {
    SetSize(fl_value_get_float(w), fl_value_get_float(h));
  }
}

void MvdLinuxWindow::SetSize(double width, double height) {
  if (!window) {
    return;
  }
  if (gtk_layer_is_layer_window(window)) {
    gtk_widget_set_size_request(GTK_WIDGET(window), static_cast<gint>(width),
                                static_cast<gint>(height));
    gtk_window_resize(window, 1, 1);
    return;
  }
  gtk_window_resize(window, static_cast<gint>(width), static_cast<gint>(height));
  if (is_modal) {
    ClampToParentBounds();
  }
}

void MvdLinuxWindow::ApplyPendingMove() {
  if (!window || !has_pending_move) return;
  has_pending_move = false;
  MVD_LOG("ApplyPendingMove  view_id=%" G_GINT64_FORMAT
          "  x=%d  y=%d  visible=%d",
          view_id, pending_move_x, pending_move_y,
          static_cast<int>(gtk_widget_get_visible(GTK_WIDGET(window))));
  // Clear any GTK position policy (e.g. GTK_WIN_POS_CENTER set by
  // complete_secondary_window when no explicit initial position was given)
  // before calling gtk_window_move. Without this the WM ignores our
  // coordinates when the window is first mapped on X11 because the policy
  // overrides the PPosition hint.
  gtk_window_set_position(window, GTK_WIN_POS_NONE);
  gtk_window_move(window, pending_move_x, pending_move_y);
}

void MvdLinuxWindow::SetPosition(double x, double y) {
  MVD_LOG("SetPosition  view_id=%" G_GINT64_FORMAT
          "  x=%.0f  y=%.0f  window=%p  visible=%d",
          view_id, x, y, static_cast<void*>(window),
          window ? static_cast<int>(gtk_widget_get_visible(GTK_WIDGET(window)))
                 : -1);
  if (!window) return;
  if (gtk_layer_is_layer_window(window)) {
    mvd_linux_move_layer_window(window, x, y, nullptr);
    return;
  }
  pending_move_x = static_cast<gint>(x);
  pending_move_y = static_cast<gint>(y);
  has_pending_move = true;
  if (gtk_widget_get_visible(GTK_WIDGET(window))) {
    // Window already visible: apply immediately.
    ApplyPendingMove();
    if (is_modal) {
      ClampToParentBounds();
    }
  }
  // Window not yet visible: has_pending_move stays true.
  // ApplyPendingMove() will be called just before gtk_widget_show() in
  // Show() and first_frame_cb so the WM receives the position at map time.
}

void MvdLinuxWindow::Center() {
  if (window) {
    gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  }
}

void MvdLinuxWindow::RefreshShadowCache() {
  // Only measure the CSD shadow in the normal (non-maximized, non-fullscreen)
  // state. In maximized/fullscreen GTK suppresses the shadow, so the delta
  // would be 0, which would wrongly overwrite a valid cached value.
  if (!window || gtk_window_is_maximized(window) || is_fullscreen) {
    return;
  }
  GdkWindow* gdk = GetGdkWindow(window);
  if (!gdk) {
    return;
  }
  gint gdk_w = gdk_window_get_width(gdk);
  gint gdk_h = gdk_window_get_height(gdk);
  gint gtk_w = 0, gtk_h = 0;
  gtk_window_get_size(window, &gtk_w, &gtk_h);
  const gint sw = (gdk_w > gtk_w) ? (gdk_w - gtk_w) : 0;
  const gint sh = (gdk_h > gtk_h) ? (gdk_h - gtk_h) : 0;

  // Re-apply hints only when the cache value actually changes (first non-zero
  // measurement, or if the shadow size changes due to theme switching).
  const bool changed = (sw > 0 && sw != cached_shadow_w) ||
                       (sh > 0 && sh != cached_shadow_h);
  if (sw > 0) { cached_shadow_w = sw; }
  if (sh > 0) { cached_shadow_h = sh; }
  if (changed && hints != static_cast<GdkWindowHints>(0)) {
    ReapplyGeometryHints();
  }
}

void MvdLinuxWindow::ReapplyGeometryHints() {
  if (!window || hints == static_cast<GdkWindowHints>(0)) {
    return;
  }

  // Use the cached shadow delta measured by RefreshShadowCache() during normal
  // window state. This avoids any live measurement here so that the function
  // works correctly regardless of the current window state (maximized,
  // fullscreen, mid-transition). RefreshShadowCache() is called from
  // on_configure (fires in every normal-state resize) and keeps the cache
  // up-to-date without touching hints on every frame.
  //
  // On Wayland or when the window is frameless the cache stays 0, which is
  // correct because the compositor uses surface-area coordinates directly.
  GdkGeometry effective = geometry;
  if (cached_shadow_w > 0 || cached_shadow_h > 0) {
    if ((hints & GDK_HINT_MIN_SIZE) && geometry.min_width >= 0) {
      effective.min_width  = geometry.min_width  + cached_shadow_w;
      effective.min_height = geometry.min_height + cached_shadow_h;
    }
    if ((hints & GDK_HINT_MAX_SIZE) && geometry.max_width < G_MAXINT) {
      effective.max_width  = geometry.max_width  + cached_shadow_w;
      effective.max_height = geometry.max_height + cached_shadow_h;
    }
  }

  gtk_window_set_geometry_hints(window, nullptr, &effective, hints);
  gtk_widget_queue_resize(GTK_WIDGET(window));
}

void MvdLinuxWindow::SetMinimumSize(float w, float h) {
  if (!window) {
    return;
  }
  if (w >= 0 && h >= 0) {
    geometry.min_width = static_cast<gint>(w);
    geometry.min_height = static_cast<gint>(h);
    hints = static_cast<GdkWindowHints>(hints | GDK_HINT_MIN_SIZE);
  } else {
    hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_MIN_SIZE);
  }
  ReapplyGeometryHints();
}

void MvdLinuxWindow::SetMaximumSize(float w, float h) {
  if (!window) {
    return;
  }
  geometry.max_width = static_cast<gint>(w);
  geometry.max_height = static_cast<gint>(h);
  if (w >= 0 && h >= 0) {
    hints = static_cast<GdkWindowHints>(hints | GDK_HINT_MAX_SIZE);
  } else {
    hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_MAX_SIZE);
  }
  if (geometry.max_width < 0) {
    geometry.max_width = G_MAXINT;
  }
  if (geometry.max_height < 0) {
    geometry.max_height = G_MAXINT;
  }
  ReapplyGeometryHints();
}

bool MvdLinuxWindow::IsResizable() {
  return is_resizable;
}

namespace {

void GetWindowContentSize(GtkWindow* window, gint* width, gint* height) {
  if (!window || !width || !height) {
    return;
  }
  gtk_window_get_size(window, width, height);
  if (*width > 0 && *height > 0) {
    return;
  }
  gtk_window_get_default_size(window, width, height);
}

}  // namespace

void MvdLinuxWindow::SetResizable(bool v) {
  is_resizable = v;
  if (!window) {
    return;
  }
  if (gtk_layer_is_layer_window(window)) return;

  if (!v) {
    gint w = 0;
    gint h = 0;
    GetWindowContentSize(window, &w, &h);
    if (w <= 0 || h <= 0) {
      gtk_window_set_resizable(window, FALSE);
      return;
    }

    if (!size_locked_by_non_resizable) {
      geometry_before_resize_lock = geometry;
      hints_before_resize_lock = hints;
      has_geometry_before_resize_lock = true;
    }

    size_locked_by_non_resizable = true;
    gtk_window_set_default_size(window, w, h);
    geometry.min_width = w;
    geometry.min_height = h;
    geometry.max_width = w;
    geometry.max_height = h;
    hints = static_cast<GdkWindowHints>(GDK_HINT_MIN_SIZE | GDK_HINT_MAX_SIZE);
    ReapplyGeometryHints();
    gtk_window_resize(window, w, h);
    gtk_window_set_resizable(window, FALSE);
    return;
  }

  gtk_window_set_resizable(window, TRUE);
  if (size_locked_by_non_resizable) {
    size_locked_by_non_resizable = false;
    if (has_geometry_before_resize_lock) {
      geometry = geometry_before_resize_lock;
      hints = hints_before_resize_lock;
      has_geometry_before_resize_lock = false;
    } else {
      geometry.min_width = -1;
      geometry.min_height = -1;
      geometry.max_width = G_MAXINT;
      geometry.max_height = G_MAXINT;
      hints = static_cast<GdkWindowHints>(0);
    }
  }

  // Clear fixed-size hints left by SetResizable(false); ReapplyGeometryHints
  // restores any min/max the caller configured via SetMinimumSize/MaximumSize.
  gtk_window_set_geometry_hints(window, nullptr, nullptr,
                                static_cast<GdkWindowHints>(0));
  ReapplyGeometryHints();
}

bool MvdLinuxWindow::IsMinimizable() {
  return is_minimizable;
}

// Updates type hint and taskbar-skip hints from stored state.
void MvdLinuxWindow::ApplyWindowTypeHint() {
  if (!window) return;
  if (is_pomo) {
    gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_UTILITY);
    gtk_window_set_skip_taskbar_hint(window, TRUE);
    gtk_window_set_skip_pager_hint(window, TRUE);
    return;
  }
  gtk_window_set_type_hint(
      window,
      is_minimizable ? GDK_WINDOW_TYPE_HINT_NORMAL : GDK_WINDOW_TYPE_HINT_DIALOG);
  gtk_window_set_skip_taskbar_hint(window, is_skip_taskbar ? TRUE : FALSE);
  gtk_window_set_skip_pager_hint(window, is_skip_taskbar ? TRUE : FALSE);
}

void MvdLinuxWindow::SetMinimizable(bool v) {
  is_minimizable = v;
  ApplyWindowTypeHint();
}

bool MvdLinuxWindow::IsMaximizable() {
  return is_maximizable;
}

void MvdLinuxWindow::SetMaximizable(bool v) {
  is_maximizable = v;
}

bool MvdLinuxWindow::IsClosable() {
  return window ? gtk_window_get_deletable(window) : false;
}

void MvdLinuxWindow::SetClosable(bool v) {
  if (window) {
    gtk_window_set_deletable(window, v);
  }
}

bool MvdLinuxWindow::IsAlwaysOnTop() {
  return is_always_on_top;
}

void MvdLinuxWindow::SetAlwaysOnTop(bool v) {
  is_always_on_top = v;
  if (window) {
    gtk_window_set_keep_above(window, v);
  }
}

const gchar* MvdLinuxWindow::GetTitle() {
  return window ? gtk_window_get_title(window) : "";
}

void MvdLinuxWindow::SetTitle(const gchar* t) {
  if (window) {
    gtk_window_set_title(window, t);
    GtkWidget* hb = HeaderBarOf(window);
    if (hb && GTK_IS_HEADER_BAR(hb)) {
      gtk_header_bar_set_title(GTK_HEADER_BAR(hb), t);
    }
  }
}

void MvdLinuxWindow::ClampWindowToConstraints() {
  if (!window || gtk_window_is_maximized(window) || is_fullscreen) {
    return;
  }
  if (hints == static_cast<GdkWindowHints>(0)) {
    return;
  }
  gint w = 0, h = 0;
  gtk_window_get_size(window, &w, &h);
  gint new_w = w, new_h = h;

  if ((hints & GDK_HINT_MIN_SIZE) && geometry.min_width >= 0) {
    if (new_w < geometry.min_width) { new_w = geometry.min_width; }
    if (new_h < geometry.min_height) { new_h = geometry.min_height; }
  }
  if ((hints & GDK_HINT_MAX_SIZE) && geometry.max_width < G_MAXINT) {
    if (new_w > geometry.max_width) { new_w = geometry.max_width; }
    if (new_h > geometry.max_height) { new_h = geometry.max_height; }
  }

  if (new_w != w || new_h != h) {
    gtk_window_resize(window, new_w, new_h);
  }
}

void MvdLinuxWindow::SetTitleBarStyle(const gchar* style, bool wbv) {
  if (!window) {
    return;
  }
  window_button_visibility = wbv;
  const bool hidden = g_strcmp0(style, "hidden") == 0;

  // Capture the current window size before any changes so we can restore it
  // in the idle callback (GTK auto-grows/shrinks by hb_h when toggling the
  // header bar, and gtk_window_resize in the idle corrects this).
  gint orig_w = 0, orig_h = 0;
  gtk_window_get_size(window, &orig_w, &orig_h);

  GtkWidget* hb = HeaderBarOf(window);
  gint hb_h = 0;
  if (hb && !gtk_window_is_maximized(window) && !is_fullscreen) {
    if (hidden && gtk_widget_is_visible(hb)) {
      // Measure and persist the header bar height while it is still visible.
      // gtk_widget_get_preferred_height of a hidden widget returns 0 on some
      // GTK versions, so we cache it here for the reverse (show) direction.
      hb_h = gtk_widget_get_allocated_height(hb);
      // g_print("[MVD]   hb_h: %d\n", hb_h);
      // if (hb_h <= 1) {
        // gtk_widget_get_preferred_height(hb, nullptr, &hb_h);
      // }
      stored_hb_h = hb_h;
    } else if (!hidden && !gtk_widget_is_visible(hb)) {
      // hb_h = stored_hb_h;
    }

  }

  if (hb) {
    if (!hidden) {
      gtk_window_set_decorated(window, TRUE);
    }
    gtk_widget_set_visible(hb, !hidden);

    gint win_w_after = 0, win_h_after = 0;
    gtk_window_get_size(window, &win_w_after, &win_h_after);
    // g_print("[MVD]   after set_visible: %dx%d\n", win_w_after, win_h_after);

    if (GTK_IS_HEADER_BAR(hb)) {
      if (wbv) {
        gtk_header_bar_set_decoration_layout(GTK_HEADER_BAR(hb), nullptr);
        gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(hb), TRUE);
      } else {
        gtk_header_bar_set_decoration_layout(GTK_HEADER_BAR(hb), ":");
        gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(hb), FALSE);
      }
    }

    // When the header bar is hidden the CSD frame still has rounded top
    // corners, but Flutter's GL content is rectangular and protrudes past
    // them. Fix: override the CSS border-radius of the window content area
    // to 0, which makes the inner visible area square-cornered so it matches
    // Flutter's rectangular rendering. The outer shadow decoration is
    // separate and remains unchanged.
    if (!csd_radius_provider) {
      csd_radius_provider = gtk_css_provider_new();
      // Use PRIORITY_USER (800) so our rule beats the theme (PRIORITY_THEME=200)
      // and application-level providers (PRIORITY_APPLICATION=600).
      // Target both window.csd (background) and decoration (shadow/border) nodes
      // since Adwaita rounds corners on both elements independently.
      gtk_style_context_add_provider(
          gtk_widget_get_style_context(GTK_WIDGET(window)),
          GTK_STYLE_PROVIDER(csd_radius_provider),
          GTK_STYLE_PROVIDER_PRIORITY_USER);
    }
    gtk_css_provider_load_from_data(
        csd_radius_provider,
        hidden ? "window.csd { border-radius: 0; }\n"
                 "decoration { border-radius: 0; }" : "",
        -1, nullptr);

    // Clear the shadow cache: it was measured with the header bar visible and
    // includes the header bar height in the GDK-GTK delta. After toggling
    // visibility the shadow extents change; on_configure will re-measure.
    cached_shadow_w = 0;
    cached_shadow_h = 0;
  } else {
    gtk_window_set_decorated(window, !hidden);
  }

  ReapplyGeometryHints();

  if (title_bar_style) {
    g_free(title_bar_style);
  }
  title_bar_style = g_strdup(style);

  // After GTK's layout pass (auto-grows/shrinks the window by hb_h and shifts
  // the content position), restore the original size AND compensate the Y
  // position so visible content stays at the same screen coordinates:
  //   HIDE: content shifts UP inside surface, move surface DOWN by hb_h.
  //   SHOW: inverse, move surface UP by hb_h.
  // if (!gtk_window_is_maximized(window) && !is_fullscreen && orig_w > 0 && orig_h > 0) {
    // struct Args { MvdLinuxWindow* self; gint w, h, hb_h; bool hidden; };
    // auto* args = new Args{this, orig_w, orig_h, hb_h, hidden};
    // g_idle_add_full(
        // G_PRIORITY_LOW,
        // [](gpointer data) -> gboolean {
          // auto* a = static_cast<Args*>(data);
          // gtk_window_resize(a->self->window, a->w, a->h);
          // gint cx = 0, cy = 0;
          // gtk_window_get_position(window, &cx, &cy);
          // GtkWindowPosition position = GtkWindowPosition();
          // gtk_window_set_position(window, GTK_WIN_POS_MOUSE);
          // if (a->hb_h > 0) {
          //   gint cx = 0, cy = 0;
          //   gtk_window_get_position(a->self->window, &cx, &cy);
          //   gtk_window_move(a->self->window, cx,
          //                   cy + (a->hidden ? a->hb_h : -a->hb_h));
          // }
          // g_print("[MVD]   hb_h3: %d\n", hb_h);
          // delete a;
          // return G_SOURCE_REMOVE;
        // },
        // args, nullptr);
  // }
}


FlValue* MvdLinuxWindow::GetTitleBarStyle() {
  const char* style = title_bar_style ? title_bar_style : "normal";
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "style", fl_value_new_string(style));
  fl_value_set_string_take(map, "windowButtonVisibility",
                           fl_value_new_bool(window_button_visibility));
  return map;
}

bool MvdLinuxWindow::IsSkipTaskbar() {
  return is_skip_taskbar;
}

void MvdLinuxWindow::SetSkipTaskbar(bool v) {
  is_skip_taskbar = v;
  ApplyWindowTypeHint();
}

double MvdLinuxWindow::GetOpacity() {
  return opacity;
}

void MvdLinuxWindow::SetOpacity(double o) {
  if (!window) {
    return;
  }
  opacity = o;
  GdkWindow* gdk = GetGdkWindow(window);
  if (gdk && o < 1.0) {
    // When the window is semi-transparent the compositor must blend it with
    // whatever is behind it. If GDK has advertised an opaque region (which
    // Flutter's GL view typically does), some compositors skip the background
    // read and produce visual trails/ghosts. Clearing the opaque region
    // forces the compositor to perform proper alpha compositing.
    gdk_window_set_opaque_region(gdk, nullptr);
  }
  gtk_widget_set_opacity(GTK_WIDGET(window), o);
}

void MvdLinuxWindow::SetBrightness(const gchar* brightness) {
  const gboolean dark = g_strcmp0(brightness, "dark") == 0;
  GtkSettings* settings = gtk_settings_get_default();
  g_object_set(settings, "gtk-application-prefer-dark-theme", dark, nullptr);
}

void MvdLinuxWindow::PopUpWindowMenu() {
  if (!window) {
    return;
  }
  auto* gdk = GetGdkWindow(window);
  if (!gdk) {
    return;
  }
  GdkDisplay* display = gdk_display_get_default();
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  int x = 0;
  int y = 0;
  gdk_device_get_position(pointer, nullptr, &x, &y);
  int ox = 0;
  int oy = 0;
  gdk_window_get_origin(gdk, &ox, &oy);
  GdkEvent* e = gdk_event_new(GDK_BUTTON_PRESS);
  e->button.window = gdk;
  e->button.device = pointer;
  e->button.x_root = x;
  e->button.y_root = y;
  e->button.x = x - ox;
  e->button.y = y - oy;
  gdk_window_show_window_menu(gdk, e);
  gdk_event_free(e);
}

void MvdLinuxWindow::StartDragging() {
  if (!window) {
    return;
  }
  auto* screen = gtk_window_get_screen(window);
  auto* display = gdk_screen_get_display(screen);
  auto* seat = gdk_display_get_default_seat(display);
  auto* device = gdk_seat_get_pointer(seat);
  gint rx = 0;
  gint ry = 0;
  gdk_device_get_position(device, nullptr, &rx, &ry);
  guint32 ts = static_cast<guint32>(g_get_monotonic_time());
  is_resizing = false;
  is_dragging = true;
  has_origin_baseline = false;
  gtk_window_begin_move_drag(window,
                           last_button.button ? last_button.button : 1, rx,
                           ry, ts);
  if (event_emitter_) {
    event_emitter_("move");
  }
  EnsureDragReleaseWatcher();
}

void MvdLinuxWindow::StartResizing(const gchar* edge) {
  if (!window) {
    return;
  }
  GdkWindowEdge ge = GDK_WINDOW_EDGE_NORTH_WEST;
  if (g_strcmp0(edge, "topLeft") == 0) {
    ge = GDK_WINDOW_EDGE_NORTH_WEST;
  } else if (g_strcmp0(edge, "top") == 0) {
    ge = GDK_WINDOW_EDGE_NORTH;
  } else if (g_strcmp0(edge, "topRight") == 0) {
    ge = GDK_WINDOW_EDGE_NORTH_EAST;
  } else if (g_strcmp0(edge, "left") == 0) {
    ge = GDK_WINDOW_EDGE_WEST;
  } else if (g_strcmp0(edge, "right") == 0) {
    ge = GDK_WINDOW_EDGE_EAST;
  } else if (g_strcmp0(edge, "bottomLeft") == 0) {
    ge = GDK_WINDOW_EDGE_SOUTH_WEST;
  } else if (g_strcmp0(edge, "bottom") == 0) {
    ge = GDK_WINDOW_EDGE_SOUTH;
  } else if (g_strcmp0(edge, "bottomRight") == 0) {
    ge = GDK_WINDOW_EDGE_SOUTH_EAST;
  }

  auto* screen = gtk_window_get_screen(window);
  auto* display = gdk_screen_get_display(screen);
  auto* seat = gdk_display_get_default_seat(display);
  auto* device = gdk_seat_get_pointer(seat);
  gint rx = 0;
  gint ry = 0;
  gdk_device_get_position(device, nullptr, &rx, &ry);
  guint32 ts = static_cast<guint32>(g_get_monotonic_time());
  is_dragging = false;
  is_resizing = true;
  has_origin_baseline = false;
  gtk_window_begin_resize_drag(window, ge,
                               last_button.button ? last_button.button : 1,
                               rx, ry, ts);
  if (event_emitter_) {
    event_emitter_("resize");
  }
  EnsureDragReleaseWatcher();
}

bool MvdLinuxWindow::IsMovable() {
  return window ? gtk_window_get_resizable(window) : true;
}

void MvdLinuxWindow::SetMovable(bool v) {
  SetResizable(v);
}

bool MvdLinuxWindow::HasShadow() {
  return true;
}

void MvdLinuxWindow::SetHasShadow(bool v) {
  (void)v;
}

// Applies pass-through to every GDK window in the widget tree.
static void apply_pass_through(GtkWidget* widget, gboolean pass_through) {
  GdkWindow* w = gtk_widget_get_window(widget);
  if (w) {
    gdk_window_set_pass_through(w, pass_through);
  }
  if (GTK_IS_CONTAINER(widget)) {
    gtk_container_forall(
        GTK_CONTAINER(widget),
        [](GtkWidget* child, gpointer data) {
          apply_pass_through(child, static_cast<gboolean>(GPOINTER_TO_INT(data)));
        },
        GINT_TO_POINTER(static_cast<gint>(pass_through)));
  }
}

void MvdLinuxWindow::SetIgnoreMouseEvents(bool ignore, bool forward) {
  is_ignore_mouse_events = ignore;
  is_forward_mouse_events = forward;
  if (!window) return;
  apply_pass_through(GTK_WIDGET(window), ignore ? TRUE : FALSE);
}

std::pair<bool, bool> MvdLinuxWindow::IsIgnoreMouseEvents() {
  return {is_ignore_mouse_events, is_forward_mouse_events};
}
