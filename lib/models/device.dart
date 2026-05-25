import 'package:flutter/foundation.dart';
import 'enums.dart';

/// A nearby device discovered on the radar (Section 6.3).
///
/// Mock devices populate the angle/distance fields directly for radar layout;
/// real native peers fill [address] and (after group formation) [ipAddress].
@immutable
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.status,
    this.signalStrength = 1.0,
    this.angle = 0.0,
    this.distance = 0.5,
    this.address,
    this.ipAddress,
  });

  final String id;
  final String name;
  final DeviceStatus status;

  /// 0–1, drives the distance indicator.
  final double signalStrength;

  /// Radial placement on the radar, in radians.
  final double angle;

  /// 0 (center) – 1 (outer ring), drives how far from center it floats.
  final double distance;

  /// WiFi Direct MAC address (only set for real native peers).
  final String? address;

  /// IP address of the peer's Group Owner socket (only set after group ready).
  final String? ipAddress;

  Device copyWith({
    DeviceStatus? status,
    double? signalStrength,
    String? address,
    String? ipAddress,
  }) =>
      Device(
        id: id,
        name: name,
        status: status ?? this.status,
        signalStrength: signalStrength ?? this.signalStrength,
        angle: angle,
        distance: distance,
        address: address ?? this.address,
        ipAddress: ipAddress ?? this.ipAddress,
      );
}
