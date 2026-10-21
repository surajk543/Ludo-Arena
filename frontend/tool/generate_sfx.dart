// Generates the app's short procedural sound effects as 16-bit mono PCM WAV
// files in assets/audio/. Deterministic (fixed PRNG seed), no dependencies.
//
// Usage (from frontend/): dart run tool/generate_sfx.dart
//
// File names must match the `Sfx` enum in
// lib/core/audio_haptics/audio_service.dart.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 22050;
const double twoPi = math.pi * 2;

/// Target peak after normalization (~ -3 dBFS).
const double targetPeak = 0.708;

/// Loudness ceiling (RMS) so effects feel balanced against each other.
const double targetRms = 0.2;

/// Deterministic xorshift PRNG so regenerated files are byte-identical.
class Rng {
  Rng(this._state);
  int _state;

  /// Uniform in [0, 1).
  double next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state / 4294967296.0;
  }

  /// Uniform in [-1, 1).
  double bipolar() => next() * 2 - 1;

  double range(double a, double b) => a + (b - a) * next();
}

/// A mono buffer of float samples in [-1, 1].
class Buffer {
  Buffer(double seconds) : data = Float64List((seconds * sampleRate).round());

  final Float64List data;

  int get length => data.length;

  /// Adds [source] starting at [atSeconds], scaled by [gain].
  void mix(Float64List source, {double atSeconds = 0, double gain = 1}) {
    final start = (atSeconds * sampleRate).round();
    for (var i = 0; i < source.length; i++) {
      final j = start + i;
      if (j < 0 || j >= data.length) continue;
      data[j] += source[i] * gain;
    }
  }
}

// ---------------------------------------------------------------- synthesis

int _n(double seconds) => (seconds * sampleRate).round();

/// Exponential decay envelope with a short linear attack.
double envExp(double t, {double attack = 0.003, double decay = 0.1}) {
  if (t < attack) return t / attack;
  return math.exp(-(t - attack) / decay);
}

/// Attack/hold/release envelope (all seconds).
double envAhr(double t, double attack, double hold, double release) {
  if (t < attack) return t / attack;
  if (t < attack + hold) return 1;
  final r = (t - attack - hold) / release;
  return r >= 1 ? 0 : (1 - r) * (1 - r);
}

/// Bell-like tone: fundamental plus soft inharmonic partials.
Float64List bell(
  double freq,
  double seconds, {
  double decay = 0.25,
  double brightness = 0.35,
}) {
  final out = Float64List(_n(seconds));
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final e = envExp(t, attack: 0.002, decay: decay);
    final s =
        math.sin(twoPi * freq * t) +
        brightness *
            math.sin(twoPi * freq * 2.0 * t) *
            math.exp(-t / (decay * 0.5)) +
        brightness *
            0.45 *
            math.sin(twoPi * freq * 2.76 * t) *
            math.exp(-t / (decay * 0.3)) +
        0.12 *
            math.sin(twoPi * freq * 4.07 * t) *
            math.exp(-t / (decay * 0.18));
    out[i] = s * e;
  }
  return out;
}

/// Wooden pluck: quickly decaying tone with a slight downward pitch drop.
Float64List pluck(
  double freq,
  double seconds, {
  double decay = 0.03,
  double drop = 0.08,
}) {
  final out = Float64List(_n(seconds));
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final f = freq * (1 + drop * math.exp(-t / 0.01));
    phase += twoPi * f / sampleRate;
    final e = envExp(t, attack: 0.0015, decay: decay);
    out[i] =
        (math.sin(phase) +
            0.35 * math.sin(2 * phase) +
            0.12 * math.sin(3 * phase)) *
        e;
  }
  return out;
}

/// Brass-like tone (band-limited sum of harmonics) for the fanfare.
Float64List brass(
  double freq,
  double seconds, {
  double attack = 0.02,
  double hold = 0.05,
  double release = 0.2,
}) {
  final out = Float64List(_n(seconds));
  const harmonics = [1.0, 0.55, 0.32, 0.18, 0.1, 0.05];
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final vib = 1 + 0.004 * math.sin(twoPi * 5.5 * t);
    var s = 0.0;
    for (var h = 0; h < harmonics.length; h++) {
      if (freq * (h + 1) > sampleRate / 2.2) break;
      s += harmonics[h] * math.sin(twoPi * freq * (h + 1) * vib * t);
    }
    out[i] = s * envAhr(t, attack, hold, release);
  }
  return out;
}

/// Soft triangle tone.
Float64List triangle(
  double freq,
  double seconds, {
  double attack = 0.01,
  double hold = 0.1,
  double release = 0.2,
  double bendTo = 1.0,
}) {
  final out = Float64List(_n(seconds));
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final p = t / seconds;
    final f = freq * (1 + (bendTo - 1) * p * p);
    phase += f / sampleRate;
    final x = phase - phase.floorToDouble();
    final tri = 4 * (x < 0.5 ? x : 1 - x) - 1;
    out[i] =
        (tri * 0.8 + 0.2 * math.sin(twoPi * phase)) *
        envAhr(t, attack, hold, release);
  }
  return out;
}

/// White noise.
Float64List noise(Rng rng, double seconds) {
  final out = Float64List(_n(seconds));
  for (var i = 0; i < out.length; i++) {
    out[i] = rng.bipolar();
  }
  return out;
}

/// One-pole low-pass, in place. [cutoff] may vary per sample.
void lowPass(Float64List x, double Function(int i) cutoff) {
  var y = 0.0;
  for (var i = 0; i < x.length; i++) {
    final c = cutoff(i);
    final a = 1 - math.exp(-twoPi * c / sampleRate);
    y += a * (x[i] - y);
    x[i] = y;
  }
}

/// One-pole high-pass, in place.
void highPass(Float64List x, double cutoff) {
  final a = math.exp(-twoPi * cutoff / sampleRate);
  var prevX = 0.0;
  var prevY = 0.0;
  for (var i = 0; i < x.length; i++) {
    final y = a * (prevY + x[i] - prevX);
    prevX = x[i];
    prevY = y;
    x[i] = y;
  }
}

/// Short percussive "wooden" click: filtered noise burst plus a resonance.
Float64List woodClick(Rng rng, double resonance, {double length = 0.035}) {
  final n = noise(rng, length);
  lowPass(n, (_) => 3500);
  final out = Float64List(n.length);
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final tone = math.sin(twoPi * resonance * t) * math.exp(-t / 0.012);
    out[i] = (0.6 * n[i] * math.exp(-t / 0.004) + 0.7 * tone);
  }
  return out;
}

// --------------------------------------------------------------- the sounds

const double c4 = 261.63, d4 = 293.66, eb4 = 311.13, f4 = 349.23, g4 = 392.0;
const double c5 = 523.25, d5 = 587.33, e5 = 659.25, g5 = 783.99, a5 = 880.0;
const double b5 = 987.77, c6 = 1046.5, e6 = 1318.51, g6 = 1567.98;

Buffer click(Rng rng) {
  final b = Buffer(0.045);
  final tick = Float64List(b.length);
  for (var i = 0; i < tick.length; i++) {
    final t = i / sampleRate;
    tick[i] = math.sin(twoPi * 2100 * t) * math.exp(-t / 0.006);
  }
  final n = noise(rng, 0.012);
  highPass(n, 2500);
  for (var i = 0; i < n.length; i++) {
    n[i] *= math.exp(-i / sampleRate / 0.002);
  }
  b
    ..mix(tick, gain: 0.8)
    ..mix(n, gain: 0.35);
  return b;
}

Buffer tokenStep(Rng rng) {
  final b = Buffer(0.1)
    ..mix(pluck(520, 0.1, decay: 0.022, drop: 0.12))
    ..mix(woodClick(rng, 1400, length: 0.02), gain: 0.25);
  return b;
}

Buffer diceRoll(Rng rng) {
  final b = Buffer(0.52);
  // Accelerating rattle that settles: decreasing gaps, decreasing loudness.
  var t = 0.0;
  var gap = 0.075;
  var gain = 0.9;
  for (var k = 0; k < 9; k++) {
    final res = rng.range(950, 1700);
    b.mix(woodClick(rng, res), atSeconds: t, gain: gain * rng.range(0.75, 1));
    if (rng.next() < 0.45) {
      b.mix(
        woodClick(rng, res * 1.31, length: 0.02),
        atSeconds: t + rng.range(0.008, 0.018),
        gain: gain * 0.4,
      );
    }
    t += gap * rng.range(0.8, 1.2);
    gap *= 0.84;
    gain *= 0.9;
  }
  // Final settle "thunk".
  b.mix(
    pluck(260, 0.12, decay: 0.03, drop: 0.2),
    atSeconds: t + 0.01,
    gain: 0.55,
  );
  return b;
}

Buffer capture(Rng rng) {
  final b = Buffer(0.48);
  final whoosh = noise(rng, 0.3);
  lowPass(whoosh, (i) {
    final p = i / whoosh.length;
    return 400 + 3800 * math.sin(math.pi * p);
  });
  for (var i = 0; i < whoosh.length; i++) {
    final p = i / whoosh.length;
    whoosh[i] *= math.pow(math.sin(math.pi * p), 1.6);
  }
  b.mix(whoosh, gain: 1.4);
  final thump = Float64List(_n(0.24));
  var phase = 0.0;
  for (var i = 0; i < thump.length; i++) {
    final tt = i / sampleRate;
    final f = 60 + 90 * math.exp(-tt / 0.03);
    phase += twoPi * f / sampleRate;
    thump[i] = math.sin(phase) * envExp(tt, attack: 0.002, decay: 0.07);
  }
  b
    ..mix(thump, atSeconds: 0.2, gain: 1.0)
    ..mix(woodClick(rng, 700, length: 0.03), atSeconds: 0.2, gain: 0.35);
  return b;
}

Buffer home(Rng rng) {
  final b = Buffer(0.75);
  const notes = [c6, e6, g6];
  for (var k = 0; k < notes.length; k++) {
    b.mix(bell(notes[k], 0.6, decay: 0.2), atSeconds: k * 0.06, gain: 0.6);
  }
  b.mix(
    bell(c6 * 2, 0.4, decay: 0.12, brightness: 0.1),
    atSeconds: 0.2,
    gain: 0.18,
  );
  return b;
}

Buffer snakeSlide(Rng rng) {
  final b = Buffer(0.72);
  final out = Float64List(b.length);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final p = t / 0.72;
    final base = 880 * math.pow(180 / 880, p);
    final f = base * (1 + 0.06 * math.sin(twoPi * 9 * t));
    phase += f / sampleRate;
    final x = phase - phase.floorToDouble();
    final tri = 4 * (x < 0.5 ? x : 1 - x) - 1;
    out[i] = tri * envAhr(t, 0.02, 0.45, 0.25);
  }
  lowPass(out, (_) => 2400);
  b.mix(out, gain: 0.9);
  return b;
}

Buffer ladderClimb(Rng rng) {
  final b = Buffer(0.66);
  const steps = [c5, d5, e5, g5, a5, c6];
  for (var k = 0; k < steps.length; k++) {
    b.mix(
      pluck(steps[k], 0.16, decay: 0.05, drop: 0.03),
      atSeconds: k * 0.085,
      gain: 0.55 + k * 0.05,
    );
  }
  return b;
}

Buffer win(Rng rng) {
  final b = Buffer(1.25);
  const arp = [c5, e5, g5];
  for (var k = 0; k < arp.length; k++) {
    b.mix(
      brass(arp[k], 0.2, attack: 0.012, hold: 0.06, release: 0.1),
      atSeconds: k * 0.11,
      gain: 0.5,
    );
  }
  // Final sustained major chord.
  for (final f in [c5, e5, g5, c6]) {
    b.mix(
      brass(f, 0.85, attack: 0.02, hold: 0.25, release: 0.55),
      atSeconds: 0.34,
      gain: 0.3,
    );
  }
  // Shimmer.
  for (var k = 0; k < 5; k++) {
    b.mix(
      bell(c6 * 2 * (1 + k * 0.125), 0.35, decay: 0.1, brightness: 0.05),
      atSeconds: 0.36 + k * 0.07,
      gain: 0.07,
    );
  }
  return b;
}

Buffer lose(Rng rng) {
  final b = Buffer(0.9);
  const notes = [g4, eb4, c4];
  for (var k = 0; k < notes.length; k++) {
    final last = k == notes.length - 1;
    b.mix(
      triangle(
        notes[k],
        last ? 0.5 : 0.24,
        attack: 0.015,
        hold: last ? 0.12 : 0.08,
        release: last ? 0.34 : 0.14,
        bendTo: last ? 0.94 : 1.0,
      ),
      atSeconds: k * 0.19,
      gain: 0.55,
    );
  }
  final out = b.data;
  lowPass(out, (_) => 1800);
  return b;
}

Buffer turn(Rng rng) {
  final b = Buffer(0.42)
    ..mix(bell(e5, 0.3, decay: 0.12, brightness: 0.2), gain: 0.55)
    ..mix(
      bell(a5, 0.3, decay: 0.15, brightness: 0.2),
      atSeconds: 0.11,
      gain: 0.55,
    );
  return b;
}

Buffer coin(Rng rng) {
  final b = Buffer(0.42);
  Float64List tone(double f, double len, double decay) {
    final out = Float64List(_n(len));
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final s =
          math.sin(twoPi * f * t) +
          0.3 * math.sin(twoPi * f * 3 * t) +
          0.12 * math.sin(twoPi * f * 5 * t);
      out[i] = s * envExp(t, attack: 0.002, decay: decay);
    }
    return out;
  }

  b
    ..mix(tone(b5, 0.08, 0.05), gain: 0.45)
    ..mix(tone(e6, 0.34, 0.11), atSeconds: 0.07, gain: 0.5)
    ..mix(
      bell(e6 * 2, 0.2, decay: 0.06, brightness: 0.05),
      atSeconds: 0.08,
      gain: 0.08,
    );
  return b;
}

Buffer levelUp(Rng rng) {
  final b = Buffer(1.0);
  const notes = [c5, e5, g5, c6, e6, g6];
  for (var k = 0; k < notes.length; k++) {
    b.mix(
      bell(notes[k], 0.5, decay: 0.16, brightness: 0.3),
      atSeconds: k * 0.065,
      gain: 0.42,
    );
  }
  // Sparkle: tiny high bell blips with random detune.
  for (var k = 0; k < 8; k++) {
    b.mix(
      bell(rng.range(2600, 4200), 0.12, decay: 0.03, brightness: 0),
      atSeconds: 0.3 + k * 0.06 + rng.range(0, 0.02),
      gain: 0.08,
    );
  }
  b.mix(
    bell(c6, 0.6, decay: 0.3, brightness: 0.25),
    atSeconds: 0.39,
    gain: 0.3,
  );
  return b;
}

Buffer chatPop(Rng rng) {
  final b = Buffer(0.13);
  final out = Float64List(b.length);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final f = 320 + 800 * (1 - math.exp(-t / 0.025));
    phase += twoPi * f / sampleRate;
    out[i] = math.sin(phase) * envExp(t, attack: 0.002, decay: 0.03);
  }
  b.mix(out, gain: 0.9);
  return b;
}

// ------------------------------------------------------------------ output

/// Normalizes to [targetPeak], applies click-free fades, converts to PCM16.
Uint8List toWav(Buffer b) {
  final x = b.data;
  // Remove DC offset.
  var mean = 0.0;
  for (final v in x) {
    mean += v;
  }
  mean /= x.length;
  for (var i = 0; i < x.length; i++) {
    x[i] -= mean;
  }
  // Fades (2 ms in, 8 ms out).
  final fadeIn = _n(0.002);
  final fadeOut = _n(0.008);
  for (var i = 0; i < fadeIn && i < x.length; i++) {
    x[i] *= i / fadeIn;
  }
  for (var i = 0; i < fadeOut && i < x.length; i++) {
    x[x.length - 1 - i] *= i / fadeOut;
  }
  var peak = 0.0;
  for (final v in x) {
    peak = math.max(peak, v.abs());
  }
  var sumSq = 0.0;
  for (final v in x) {
    sumSq += v * v;
  }
  final rms = math.sqrt(sumSq / x.length);
  // Peak-normalize, but cap loudness (RMS) so sustained tones (snake slide,
  // lose) don't sound louder than percussive UI ticks.
  final gain = peak == 0
      ? 1.0
      : math.min(
          targetPeak / peak,
          rms == 0 ? double.infinity : targetRms / rms,
        );

  final dataBytes = x.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // PCM chunk size
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < x.length; i++) {
    final s = (x[i] * gain).clamp(-1.0, 1.0);
    bytes.setInt16(44 + i * 2, (s * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  final effects = <String, Buffer Function(Rng)>{
    'dice_roll': diceRoll,
    'token_step': tokenStep,
    'capture': capture,
    'home': home,
    'snake_slide': snakeSlide,
    'ladder_climb': ladderClimb,
    'win': win,
    'lose': lose,
    'click': click,
    'turn': turn,
    'coin': coin,
    'level_up': levelUp,
    'chat_pop': chatPop,
  };
  final dir = Directory('assets/audio')..createSync(recursive: true);
  var total = 0;
  var seed = 0x2F6E2B1;
  for (final entry in effects.entries) {
    final wav = toWav(entry.value(Rng(seed)));
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    File('${dir.path}/${entry.key}.wav').writeAsBytesSync(wav);
    total += wav.length;
    stdout.writeln(
      '${entry.key.padRight(14)} ${(wav.length / 1024).toStringAsFixed(1).padLeft(6)} KB',
    );
  }
  stdout.writeln(
    'total          ${(total / 1024).toStringAsFixed(1).padLeft(6)} KB',
  );
  if (total > 600 * 1024) {
    stderr.writeln('Sound effects exceed the 600 KB budget.');
    exitCode = 1;
  }
}
