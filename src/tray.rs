use std::process::Command;
use std::time::Duration;

use ksni::blocking::TrayMethods;
use ksni::menu::StandardItem;
use ksni::{Icon, MenuItem, ToolTip};

use crate::state;

const MODULE_ID: &str = "io.github.alexmrtr.oma-channel";
const POLL_INTERVAL: Duration = Duration::from_secs(30);

struct OmaChannelTray {
    unread: usize,
}

impl ksni::Tray for OmaChannelTray {
    fn id(&self) -> String {
        MODULE_ID.into()
    }

    fn title(&self) -> String {
        "Oma Channel".into()
    }

    fn icon_pixmap(&self) -> Vec<Icon> {
        vec![icon()]
    }

    fn tool_tip(&self) -> ToolTip {
        ToolTip {
            title: "Oma Channel".into(),
            description: if self.unread > 0 {
                format!("{} não lidos", self.unread)
            } else {
                "Nenhum artigo não lido".into()
            },
            ..Default::default()
        }
    }

    // Primary click: same toggle the bar icon itself would trigger.
    fn activate(&mut self, _x: i32, _y: i32) {
        run_ipc(&["shell", "toggle", MODULE_ID]);
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        vec![
            StandardItem {
                label: "Abrir".into(),
                activate: Box::new(|_| run_ipc(&["shell", "toggle", MODULE_ID])),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Atualizar agora".into(),
                activate: Box::new(|_| run_ipc(&[MODULE_ID, "refresh"])),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Marcar tudo como lido".into(),
                activate: Box::new(|_| run_ipc(&[MODULE_ID, "markAllRead"])),
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: "Salvos".into(),
                activate: Box::new(|_| run_ipc(&[MODULE_ID, "bookmarks"])),
                ..Default::default()
            }
            .into(),
        ]
    }
}

/// Fires an existing IPC command as a detached subprocess -- the same
/// `omarchy-shell ...` surface already used for hotkeys, just triggered from
/// the tray instead. Errors are logged, never allowed to crash the tray loop.
fn run_ipc(args: &[&str]) {
    if let Err(err) = Command::new("omarchy-shell").args(args).spawn() {
        eprintln!("warn: omarchy-shell {}: {err:#}", args.join(" "));
    }
}

/// A small solid-color circle, generated at runtime rather than shipped as an
/// asset -- avoids an image-decoding dependency for one 32x32 dot. ARGB32,
/// network byte order (big-endian: A, R, G, B per pixel), per ksni::Icon's
/// documented format.
fn icon() -> Icon {
    const SIZE: i32 = 32;
    const RADIUS: f32 = SIZE as f32 * 0.42;
    let center = (SIZE as f32 - 1.0) / 2.0;
    let mut data = vec![0u8; (SIZE * SIZE * 4) as usize];
    for y in 0..SIZE {
        for x in 0..SIZE {
            let dx = x as f32 - center;
            let dy = y as f32 - center;
            let idx = ((y * SIZE + x) * 4) as usize;
            if dx * dx + dy * dy <= RADIUS * RADIUS {
                data[idx] = 255; // A
                data[idx + 1] = 255; // R
                data[idx + 2] = 160; // G
                data[idx + 3] = 0; // B -- solid feed-orange
            }
        }
    }
    Icon {
        width: SIZE,
        height: SIZE,
        data,
    }
}

fn current_unread(path: &std::path::Path) -> usize {
    state::load_state(path)
        .map(|st| st.unread_count())
        .unwrap_or(0)
}

/// Publishes the tray icon and keeps its tooltip's unread count current.
/// Runs until the process is killed by its parent (Service.qml owns the
/// lifecycle of this as a long-running Process).
pub fn run(state_path: &std::path::Path) -> anyhow::Result<()> {
    let tray = OmaChannelTray {
        unread: current_unread(state_path),
    };
    let handle = tray
        .spawn()
        .map_err(|e| anyhow::anyhow!("tray registration failed: {e}"))?;

    loop {
        std::thread::sleep(POLL_INTERVAL);
        if handle.is_closed() {
            break;
        }
        let unread = current_unread(state_path);
        handle.update(|t: &mut OmaChannelTray| t.unread = unread);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn icon_has_argb32_sized_buffer() {
        let img = icon();
        assert_eq!(img.width, 32);
        assert_eq!(img.height, 32);
        assert_eq!(img.data.len(), (img.width * img.height * 4) as usize);
    }

    #[test]
    fn icon_center_is_opaque_and_corner_is_transparent() {
        let img = icon();
        let px = |x: i32, y: i32| {
            let idx = ((y * img.width + x) * 4) as usize;
            (img.data[idx], img.data[idx + 1], img.data[idx + 2], img.data[idx + 3])
        };
        let (a, r, g, b) = px(16, 16);
        assert_eq!(a, 255);
        assert_eq!((r, g, b), (255, 160, 0));
        let (corner_a, _, _, _) = px(0, 0);
        assert_eq!(corner_a, 0);
    }
}
