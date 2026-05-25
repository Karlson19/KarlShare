// Shared enums for Karlshare domain models.

enum DeviceStatus { ready, busy, connecting }

enum TransferDirection { sent, received }

enum TransferStatus { pending, transferring, paused, completed, failed }

/// Coarse file categories used for icons, tabs and previews.
enum KFileType { image, video, audio, document, app, other }
