import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/ui/files/widgets/file_icon.dart';

void main() {
  test('extension matching is case insensitive and precedes generic MIME', () {
    expect(
      fileIcon('Budget.XLSX', 'application/octet-stream'),
      LucideIcons.fileSpreadsheet,
    );
    expect(fileIcon('Letter.docx', 'text/plain'), LucideIcons.fileType);
    expect(
      fileIcon('readme.TXT', 'application/octet-stream'),
      LucideIcons.fileText,
    );
    expect(
      fileIcon('scan.pdf', 'application/octet-stream'),
      LucideIcons.fileScan,
    );
    expect(fileIcon('deck.pptx', ''), LucideIcons.fileChartColumn);
    expect(fileIcon('backup.tar.gz', ''), LucideIcons.fileArchive);
    expect(fileIcon('song.mp3', ''), LucideIcons.fileMusic);
    expect(fileIcon('clip.mp4', ''), LucideIcons.fileVideoCamera);
    expect(fileIcon('main.dart', ''), LucideIcons.fileCode);
  });
  test(
    'MIME fallback handles missing extensions, parameters and unknown files',
    () {
      expect(
        fileIcon('download', 'text/plain; charset=utf-8'),
        LucideIcons.fileText,
      );
      expect(
        fileIcon('download', 'application/vnd.ms-excel'),
        LucideIcons.fileSpreadsheet,
      );
      expect(fileIcon('download', 'application/msword'), LucideIcons.fileType);
      expect(fileIcon('download', 'application/pdf'), LucideIcons.fileScan);
      expect(fileIcon('download', 'video/mp4'), LucideIcons.fileVideoCamera);
      expect(fileIcon('download', 'audio/ogg'), LucideIcons.fileMusic);
      expect(fileIcon('download', 'application/zip'), LucideIcons.fileArchive);
      expect(fileIcon('download', 'image/svg+xml'), LucideIcons.fileImage);
      expect(fileIcon('download', 'application/json'), LucideIcons.fileCode);
      expect(fileIcon('xlsx', ''), LucideIcons.file);
      expect(
        fileIcon('unknown.bin', 'application/octet-stream'),
        LucideIcons.file,
      );
    },
  );
}
