import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

IconData fileIcon(String name, String contentType) {
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  final icon = switch (extension) {
    'xls' || 'xlsx' || 'xlsm' || 'csv' || 'ods' => LucideIcons.fileSpreadsheet,
    'doc' || 'docx' || 'odt' || 'rtf' => LucideIcons.fileType,
    'txt' || 'md' || 'log' => LucideIcons.fileText,
    'pdf' => LucideIcons.fileScan,
    'ppt' || 'pptx' || 'odp' => LucideIcons.fileChartColumn,
    'zip' ||
    'rar' ||
    '7z' ||
    'tar' ||
    'gz' ||
    'bz2' ||
    'xz' => LucideIcons.fileArchive,
    'mp3' ||
    'wav' ||
    'ogg' ||
    'flac' ||
    'm4a' ||
    'aac' => LucideIcons.fileMusic,
    'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => LucideIcons.fileVideoCamera,
    'dart' ||
    'js' ||
    'ts' ||
    'jsx' ||
    'tsx' ||
    'json' ||
    'html' ||
    'htm' ||
    'css' ||
    'xml' ||
    'yaml' ||
    'yml' ||
    'py' ||
    'go' ||
    'rs' ||
    'java' ||
    'c' ||
    'cpp' ||
    'h' ||
    'sh' ||
    'sql' => LucideIcons.fileCode,
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'avif' ||
    'svg' ||
    'bmp' ||
    'tif' ||
    'tiff' ||
    'heic' => LucideIcons.fileImage,
    _ => null,
  };
  if (icon != null) return icon;
  final mime = contentType.split(';').first.trim().toLowerCase();
  return switch (mime) {
    'application/vnd.ms-excel' ||
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    'application/vnd.oasis.opendocument.spreadsheet' ||
    'text/csv' => LucideIcons.fileSpreadsheet,
    'application/msword' ||
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
    'application/vnd.oasis.opendocument.text' ||
    'application/rtf' => LucideIcons.fileType,
    'application/pdf' => LucideIcons.fileScan,
    'application/vnd.ms-powerpoint' ||
    'application/vnd.openxmlformats-officedocument.presentationml.presentation' ||
    'application/vnd.oasis.opendocument.presentation' =>
      LucideIcons.fileChartColumn,
    'application/zip' ||
    'application/x-zip-compressed' ||
    'application/x-7z-compressed' ||
    'application/vnd.rar' ||
    'application/x-rar-compressed' ||
    'application/gzip' ||
    'application/x-tar' => LucideIcons.fileArchive,
    'application/json' ||
    'application/xml' ||
    'application/javascript' ||
    'text/javascript' ||
    'text/html' ||
    'text/css' ||
    'text/xml' => LucideIcons.fileCode,
    _ when mime.startsWith('text/') => LucideIcons.fileText,
    _ when mime.startsWith('audio/') => LucideIcons.fileMusic,
    _ when mime.startsWith('video/') => LucideIcons.fileVideoCamera,
    _ when mime.startsWith('image/') => LucideIcons.fileImage,
    _ => LucideIcons.file,
  };
}
