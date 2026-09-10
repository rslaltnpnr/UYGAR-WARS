import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'cat_sprite.dart';

/// Uygulama ekraninin sinirlari icinde (masaustu surumundeki "dolasma"
/// davranisinin ayni mantigi, ama masaustune degil bu ekrana sinirli)
/// rastgele hedefler arasinda gezinen kedi. Dokununca [onTap], basili
/// tutunca [onLongPress] tetiklenir.
class RoamingCat extends StatefulWidget {
  final Size bounds;
  final CatState state;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const RoamingCat({
    super.key,
    required this.bounds,
    required this.state,
    required this.size,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<RoamingCat> createState() => _RoamingCatState();
}

class _RoamingCatState extends State<RoamingCat> {
  final _random = Random();
  Offset _position = Offset.zero;
  bool _facingLeft = false;
  Duration _moveDuration = const Duration(seconds: 1);
  Timer? _timer;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized &&
        widget.bounds.width > widget.size &&
        widget.bounds.height > widget.size) {
      _initialized = true;
      _position = _randomPosition();
      _scheduleNextMove();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Offset _randomPosition() {
    final maxX = max(0.0, widget.bounds.width - widget.size);
    final maxY = max(0.0, widget.bounds.height - widget.size);
    return Offset(_random.nextDouble() * maxX, _random.nextDouble() * maxY);
  }

  void _scheduleNextMove() {
    _timer = Timer(
      Duration(milliseconds: 1500 + _random.nextInt(3500)),
      _moveToNewSpot,
    );
  }

  void _moveToNewSpot() {
    if (!mounted) return;
    // "stern" (dusunuyor), "zzz" (uyuyor) gibi durumlarda yerinde kalir.
    if (widget.state != CatState.norm) {
      _scheduleNextMove();
      return;
    }
    final target = _randomPosition();
    final distance = (target - _position).distance;
    setState(() {
      _facingLeft = target.dx < _position.dx;
      _position = target;
      _moveDuration = Duration(
        milliseconds: (distance * 6).clamp(600, 3500).toInt(),
      );
    });
    _scheduleNextMove();
  }

  @override
  Widget build(BuildContext context) {
    final sprite = Transform(
      alignment: Alignment.center,
      transform: _facingLeft
          ? (Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0))
          : Matrix4.identity(),
      child: CatSprite(state: widget.state, size: widget.size),
    );

    return AnimatedPositioned(
      duration: _moveDuration,
      curve: Curves.easeInOut,
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: sprite,
      ),
    );
  }
}
