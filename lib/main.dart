import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/collisions.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(GameWidget(game: NeonLaneGame()));
}

enum GameState { menu, playing, paused, gameOver }
enum ObjectType { policeBlock, roadBarrier, loot, shield }

class NeonLaneGame extends FlameGame with DragCallbacks, HasCollisionDetection, TapCallbacks {
  late Player player;
  late PolicePersever police;
  GameState state = GameState.menu;

  double gameSpeed = 500.0;
  double score = 0;
  double highScore = 0; // Puntaje máximo cargado

  int _lastSpawnFrame = 0;
  final Random _rng = Random();
  late SharedPreferences _prefs;

  double _lightTimer = 0;
  bool useRedLights = true;

  @override
  Color backgroundColor() => const Color(0xFF333333);

  @override
  Future<void> onLoad() async {
    // Inicializar preferencias y cargar High Score
    _prefs = await SharedPreferences.getInstance();
    highScore = _prefs.getDouble('highScore') ?? 0;

    await FlameAudio.audioCache.loadAll([
      'sirena.mp3', 'click.mp3', 'error.mp3', 'correct.mp3', 'ping.mp3'
    ]);

    add(AsphaltRoad());
    police = PolicePersever();
    add(police);
    player = Player();
    add(player);
  }

  void startGame() {
    state = GameState.playing;
    score = 0;
    gameSpeed = 500.0;
    _lastSpawnFrame = 0;
    player.reset();
    police.reset();
    children.whereType<RoadObject>().forEach((e) => e.removeFromParent());
    resumeEngine();
    if (!FlameAudio.bgm.isPlaying) {
      FlameAudio.bgm.play('sirena.mp3', volume: 0.15);
    }
  }

  void pauseGame() {
    state = GameState.paused;
    pauseEngine();
  }

  void resumeGame() {
    state = GameState.playing;
    resumeEngine();
  }

  void gameOver() async {
    state = GameState.gameOver;
    FlameAudio.bgm.stop();
    FlameAudio.play('error.mp3');

    // GUARDAR RECORD si el actual es mayor
    if (score > highScore) {
      highScore = score;
      await _prefs.setDouble('highScore', highScore);
    }

    pauseEngine();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (state == GameState.playing) {
      gameSpeed += 15 * dt;
      score += dt * (gameSpeed / 50);

      _lastSpawnFrame++;
      if (_lastSpawnFrame > max(25, 45 - (gameSpeed / 150).toInt())) {
        _generateWave();
        _lastSpawnFrame = 0;
      }

      _lightTimer += dt;
      if (_lightTimer > 0.12) {
        useRedLights = !useRedLights;
        _lightTimer = 0;
      }
    }
  }

  void _generateWave() {
    int objectsToSpawn = _rng.nextDouble() < 0.3 ? 2 : 1;
    List<int> lanes = [0, 1, 2]..shuffle();

    for (int i = 0; i < objectsToSpawn; i++) {
      int lane = lanes[i];
      double typeChance = _rng.nextDouble();

      if (typeChance < 0.75) {
        ObjectType obstacle = _rng.nextBool() ? ObjectType.policeBlock : ObjectType.roadBarrier;
        add(RoadObject(lane, gameSpeed, obstacle));
      } else if (typeChance < 0.90) {
        add(RoadObject(lane, gameSpeed, ObjectType.loot));
      } else {
        add(RoadObject(lane, gameSpeed, ObjectType.shield));
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (state == GameState.playing) {
      _drawText(canvas, "BOTÍN: \$${score.toInt()}", 22, Colors.amber, Offset(20, 50), true, Anchor.topLeft);
      canvas.drawCircle(Offset(size.x - 45, 50), 25, Paint()..color = Colors.white24);
      _drawText(canvas, "||", 20, Colors.white, Offset(size.x - 45, 50), false, Anchor.center);
    }

    else if (state == GameState.menu) {
      _drawMenuBox(canvas, "NEON LANE", ["JUGAR", "SALIR"], showHighscore: true);
    }

    else if (state == GameState.paused) {
      _drawMenuBox(canvas, "PAUSA", ["REANUDAR", "REINICIAR", "SALIR"]);
    }

    else if (state == GameState.gameOver) {
      _drawMenuBox(canvas, "¡ARRESTADO!", ["REINTENTAR", "MENÚ"], showCurrentScore: true);
    }
  }

  void _drawMenuBox(Canvas canvas, String title, List<String> options, {bool showHighscore = false, bool showCurrentScore = false}) {
    canvas.drawRect(size.toRect(), Paint()..color = Colors.black.withOpacity(0.8));

    double boxWidth = 280;
    double boxHeight = 120 + (options.length * 80);
    final boxRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(size.x/2, size.y/2), width: boxWidth, height: boxHeight),
        const Radius.circular(20)
    );

    canvas.drawRRect(boxRect, Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawRRect(boxRect, Paint()..color = Colors.redAccent.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 3);

    _drawText(canvas, title, 32, Colors.redAccent, Offset(size.x/2, size.y/2 - (boxHeight/2) + 40), true, Anchor.center);

    // Mostrar el High Score en el menú principal o Game Over
    if (showHighscore || showCurrentScore) {
      String subText = showHighscore ? "RECORD: \$${highScore.toInt()}" : "PUNTAJE: \$${score.toInt()}";
      _drawText(canvas, subText, 18, Colors.amberAccent, Offset(size.x/2, size.y/2 - (boxHeight/2) + 80), false, Anchor.center);
    }

    for (int i = 0; i < options.length; i++) {
      double y = size.y/2 - (boxHeight/2) + 150 + (i * 80);
      final btnRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(size.x/2, y), width: 200, height: 50),
          const Radius.circular(10)
      );
      canvas.drawRRect(btnRect, Paint()..color = Colors.white10);
      canvas.drawRRect(btnRect, Paint()..color = Colors.white30..style = PaintingStyle.stroke..strokeWidth = 1);
      _drawText(canvas, options[i], 20, Colors.white, Offset(size.x/2, y), false, Anchor.center);
    }
  }

  void _drawText(Canvas canvas, String text, double size, Color color, Offset off, bool glow, Anchor anchor) {
    final tp = TextPainter(
        text: TextSpan(
            style: TextStyle(
                color: color, fontSize: size, fontWeight: FontWeight.bold, fontFamily: 'monospace',
                shadows: glow ? [Shadow(color: color, blurRadius: 15)] : []
            ),
            text: text
        ),
        textDirection: TextDirection.ltr
    )..layout();
    Offset p = anchor == Anchor.center ? off - Offset(tp.width/2, tp.height/2) : (anchor == Anchor.topLeft ? off : off - Offset(tp.width, 0));
    tp.paint(canvas, p);
  }

  @override
  void onTapDown(TapDownEvent event) {
    final pos = event.localPosition;

    if (state == GameState.playing) {
      if (pos.x > size.x - 80 && pos.y < 100) pauseGame();
    } else {
      List<String> currentOptions = [];
      if (state == GameState.menu) currentOptions = ["JUGAR", "SALIR"];
      if (state == GameState.paused) currentOptions = ["REANUDAR", "REINICIAR", "SALIR"];
      if (state == GameState.gameOver) currentOptions = ["REINTENTAR", "MENÚ"];

      double boxHeight = 120 + (currentOptions.length * 80);
      double startY = size.y/2 - (boxHeight/2) + 150;

      for (int i = 0; i < currentOptions.length; i++) {
        double btnY = startY + (i * 80);
        if (pos.x > size.x/2 - 100 && pos.x < size.x/2 + 100 && pos.y > btnY - 25 && pos.y < btnY + 25) {
          _handleMenuClick(i);
          break;
        }
      }
    }
  }

  void _handleMenuClick(int index) {
    FlameAudio.play('click.mp3');
    if (state == GameState.menu) {
      if (index == 0) startGame();
      if (index == 1) SystemNavigator.pop();
    }
    else if (state == GameState.paused) {
      if (index == 0) resumeGame();
      if (index == 1) startGame();
      if (index == 2) { state = GameState.menu; resumeEngine(); }
    }
    else if (state == GameState.gameOver) {
      if (index == 0) startGame();
      if (index == 1) { state = GameState.menu; resumeEngine(); }
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (state == GameState.playing) {
      double laneWidth = size.x / 3;
      player.currentLane = (event.localEndPosition.x / laneWidth).floor().clamp(0, 2);
    }
  }
}

// (El resto de clases Player, PolicePersever, RoadObject y AsphaltRoad se mantienen igual que la versión anterior)

mixin PoliceLights on SpriteComponent, HasGameRef<NeonLaneGame> {
  void renderLights(Canvas canvas, double verticalPositionFactor, {double thicknessFactor = 1.0}) {
    if (gameRef.state == GameState.menu) return;
    final lightWidth = size.x * 0.12;
    final lightHeight = (size.y * 0.035) * thicknessFactor;
    final verticalPos = size.y * verticalPositionFactor;
    final radius = Radius.circular(lightHeight / 2);
    canvas.save();
    canvas.translate(size.x / 2, verticalPos);
    if (gameRef.useRedLights) {
      canvas.drawRRect(RRect.fromLTRBAndCorners(-lightWidth, -lightHeight/2, 0, lightHeight/2, topLeft: radius, bottomLeft: radius), Paint()..color = Colors.redAccent);
      canvas.drawRRect(RRect.fromLTRBAndCorners(0, -lightHeight/2, lightWidth, lightHeight/2, topRight: radius, bottomRight: radius), Paint()..color = Colors.blue[900]!);
    } else {
      canvas.drawRRect(RRect.fromLTRBAndCorners(0, -lightHeight/2, lightWidth, lightHeight/2, topRight: radius, bottomRight: radius), Paint()..color = Colors.cyanAccent);
      canvas.drawRRect(RRect.fromLTRBAndCorners(-lightWidth, -lightHeight/2, 0, lightHeight/2, topLeft: radius, bottomLeft: radius), Paint()..color = Colors.red[900]!);
    }
    canvas.restore();
  }
}

class Player extends SpriteComponent with HasGameRef<NeonLaneGame>, CollisionCallbacks {
  int currentLane = 1;
  bool hasShield = false;
  Player() : super(size: Vector2(90, 120), anchor: Anchor.center);
  @override
  Future<void> onLoad() async {
    sprite = await gameRef.loadSprite('player_car.png');
    add(RectangleHitbox(size: size * 0.8, position: size * 0.1));
  }
  void reset() { currentLane = 1; position = Vector2(gameRef.size.x / 2, gameRef.size.y - 200); hasShield = false; }
  @override
  void update(double dt) {
    if (gameRef.state != GameState.playing) return;
    super.update(dt);
    double laneWidth = gameRef.size.x / 3;
    position.x += ((currentLane * laneWidth + laneWidth/2) - position.x) * 0.2;
  }
  @override
  void render(Canvas canvas) {
    if (gameRef.state == GameState.menu) return;
    super.render(canvas);
    if (hasShield) canvas.drawCircle(Offset(size.x/2, size.y/2), size.y * 0.5, Paint()..color = Colors.cyanAccent.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 4);
  }
  @override
  void onCollisionStart(Set<Vector2> points, PositionComponent other) {
    if (other is RoadObject) {
      if (other.type == ObjectType.policeBlock || other.type == ObjectType.roadBarrier) {
        if (hasShield) { hasShield = false; other.removeFromParent(); FlameAudio.play('ping.mp3'); }
        else { gameRef.gameOver(); }
      } else if (other.type == ObjectType.loot) {
        gameRef.score += 250; FlameAudio.play('correct.mp3'); other.removeFromParent();
      } else if (other.type == ObjectType.shield) {
        hasShield = true; FlameAudio.play('ping.mp3'); other.removeFromParent();
      }
    }
    super.onCollisionStart(points, other);
  }
}

class PolicePersever extends SpriteComponent with HasGameRef<NeonLaneGame>, PoliceLights {
  double targetY = 0;
  int currentTargetLane = 1;
  PolicePersever() : super(size: Vector2(90, 120), anchor: Anchor.center);
  @override
  Future<void> onLoad() async { sprite = await gameRef.loadSprite('police_car.png'); }
  void reset() { targetY = gameRef.size.y - 60; position = Vector2(gameRef.size.x / 2, gameRef.size.y + 200); currentTargetLane = 1; }
  @override
  void update(double dt) {
    if (gameRef.state != GameState.playing) return;
    super.update(dt);
    bool pathBlocked = gameRef.children.whereType<RoadObject>().any((obj) =>
    obj.lane == gameRef.player.currentLane && obj.position.y < position.y && obj.position.y > position.y - 400 &&
        (obj.type == ObjectType.policeBlock || obj.type == ObjectType.roadBarrier)
    );
    if (!pathBlocked) currentTargetLane = gameRef.player.currentLane;
    double laneWidth = gameRef.size.x / 3;
    position.x += ((currentTargetLane * laneWidth + laneWidth/2) - position.x) * 0.04;
    position.y += (targetY - position.y) * 0.03;
    if (position.y <= gameRef.player.position.y + 65) gameRef.gameOver();
  }
  @override
  void render(Canvas canvas) {
    if (gameRef.state == GameState.menu) return;
    super.render(canvas);
    renderLights(canvas, 0.51, thicknessFactor: 2.0);
  }
}

class RoadObject extends SpriteComponent with HasGameRef<NeonLaneGame>, CollisionCallbacks, PoliceLights {
  final int lane; final double speed; final ObjectType type; bool isTripleBarrier = false;
  RoadObject(this.lane, this.speed, this.type) : super(size: Vector2(80, 80), anchor: Anchor.center);
  @override
  Future<void> onLoad() async {
    switch (type) {
      case ObjectType.policeBlock: sprite = await gameRef.loadSprite('police_block.png'); size = Vector2(95, 125); add(RectangleHitbox()); break;
      case ObjectType.roadBarrier: sprite = await gameRef.loadSprite('road_barrier.png'); size = Vector2(40, 40); isTripleBarrier = true; add(RectangleHitbox(size: Vector2(120, 40), position: Vector2(-40, 0))); break;
      case ObjectType.loot: sprite = await gameRef.loadSprite('loot_cash.png'); size = Vector2(60, 60); add(RectangleHitbox()); break;
      case ObjectType.shield: sprite = await gameRef.loadSprite('shield_powerup.png'); size = Vector2(60, 60); add(RectangleHitbox()); break;
    }
    double laneWidth = gameRef.size.x / 3;
    position = Vector2((lane * laneWidth) + (laneWidth / 2), -200);
  }
  @override
  void render(Canvas canvas) {
    if (isTripleBarrier && sprite != null) {
      sprite!.render(canvas, position: Vector2(-size.x, 0), size: size);
      sprite!.render(canvas, position: Vector2(0, 0), size: size);
      sprite!.render(canvas, position: Vector2(size.x, 0), size: size);
    } else {
      super.render(canvas);
      if (type == ObjectType.policeBlock) renderLights(canvas, 0.33);
    }
  }
  @override
  void update(double dt) {
    if (gameRef.state != GameState.playing) return;
    position.y += speed * dt;
    if (position.y > gameRef.size.y + 200) removeFromParent();
  }
}

class AsphaltRoad extends Component with HasGameRef<NeonLaneGame> {
  double offset = 0;
  @override
  void update(double dt) {
    if (gameRef.state == GameState.playing) {
      offset += gameRef.gameSpeed * dt;
      if (offset > 80) offset = 0;
    }
  }
  @override
  void render(Canvas canvas) {
    final width = gameRef.size.x; final height = gameRef.size.y;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xFF444444));
    final grassPaint = Paint()..color = const Color(0xFF2E7D32);
    canvas.drawRect(Rect.fromLTWH(0, 0, 15, height), grassPaint);
    canvas.drawRect(Rect.fromLTWH(width - 15, 0, 15, height), grassPaint);
    final linePaint = Paint()..color = Colors.white.withOpacity(0.6)..strokeWidth = 4;
    for (int i = 1; i < 3; i++) {
      double x = i * (width / 3);
      for (double y = -80 + offset; y < height; y += 80) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 40), linePaint);
      }
    }
  }
}
