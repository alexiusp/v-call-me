/// ICE candidate types this app transmits, per DESIGN.md section 4.
/// `prflx` (peer-reflexive) candidates are never sent - they're only ever
/// discovered locally during connectivity checks, never gathered ahead of
/// time, so they have no place in the pre-gathered compact payload.
enum CandidateType { host, srflx, relay }

enum CandidateTransport { udp, tcp }

/// One ICE candidate, restricted to the fields DESIGN.md section 4 actually
/// transmits (IPv4 only for v1; foundation/priority are regenerated locally
/// on the receiving end rather than sent over the wire).
class IceCandidateInfo {
  const IceCandidateInfo({
    required this.type,
    required this.transport,
    required this.ip,
    required this.port,
  });

  final CandidateType type;
  final CandidateTransport transport;

  /// Dotted-quad IPv4 address, e.g. "192.168.1.5".
  final String ip;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is IceCandidateInfo &&
      other.type == type &&
      other.transport == transport &&
      other.ip == ip &&
      other.port == port;

  @override
  int get hashCode => Object.hash(type, transport, ip, port);

  @override
  String toString() =>
      'IceCandidateInfo(type: $type, transport: $transport, ip: $ip, port: $port)';
}
