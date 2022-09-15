import 'package:meta/meta.dart';
import 'dart:math' as math;

import 'package:mobx/mobx.dart' as mobx;
// ignore: implementation_imports
import 'package:mobx/src/core.dart' show ReactionImpl;

import 'obs.dart';

export 'obs.dart';

T useTrack<T>(
  T Function() compute,
  void Function() onDependencyChange, {
  String? name,
}) {
  final reaction = useRef<ReactionImpl>(
    () {
      final _name = name ?? mobx.mainContext.nameFor('useTrack');
      return ReactionImpl(
        mobx.mainContext,
        () {
          print('$_name dependency-change');
          onDependencyChange();
        },
        name: _name,
        onError: (err, stackTrace) => print('useTrack $_name $err $stackTrace'),
      );
    },
  ).value;
  useEffect(
    () => reaction.dispose,
    const [],
  );

  late final T trackedValue;
  reaction.track(() {
    print('${reaction.name} start-track');
    trackedValue = compute();
    print('${reaction.name} end-track');
  });
  return trackedValue;
}

class Ref<T> {
  Ref(this.value);
  T value;

  @override
  String toString() {
    return 'Ref($value)';
  }
}

/// A function to be called to cleanup an effect.
typedef Cleanup = void Function();

/// An [Effect] is a function to be called when a
/// component was (re)rendered.
typedef Effect = Cleanup? Function();

typedef KeysEquals = bool Function(Object?, Object?);

class HookEffect {
  final Effect effect;
  final List<Object?>? keys;
  final KeysEquals isEqual;
  Cleanup? cleanup;

  HookEffect({
    required this.effect,
    required this.keys,
    required this.isEqual,
  });
}

bool defaultKeysEquals(Object? a, Object? b) => a == b;

HookCtx? __globalHookContext;
HookCtx get globalHookContext {
  assert(
    __globalHookContext != null,
    'Current HookCtx is null ${StackTrace.current}',
  );
  return __globalHookContext!;
}

@experimental
class HookCtxConfig {
  final void Function(HookCtx? previous, void Function() execute)?
      effectsScheduler;

  const HookCtxConfig({
    this.effectsScheduler,
  });

  static HookCtxConfig global = const HookCtxConfig();
}

class _HookCtxState {
  int? _hookRefIndex;
  final List<Ref> _hookRefs = [];
  int? _hookObsIndex;
  final List<Obs> _hookObs = [];

  List<HookEffect> _hookEffects = [];
  List<HookEffect> _previousHookEffects = [];

  void _reset() {
    _previousHookEffects = _hookEffects;
    _hookEffects = [];

    _hookRefIndex = 0;
    _hookObsIndex = 0;
  }
}

class HookCtx {
  _HookCtxState? __state;
  _HookCtxState get _state => __state ??= _HookCtxState();
  bool get hasState => __state != null;

  bool _disposed = false;
  bool get disposed => _disposed;
  HookCtx? _previous;
  HookCtx? _next;
  bool _scheduled = false;

  HookCtx(this._onDependencyChange);
  final void Function() _onDependencyChange;

  String get _name => hashCode.toString();

  late final _reaction = ReactionImpl(
    mobx.mainContext,
    () {
      print('$_name dependency-change');
      _onDependencyChange();
    },
    name: _name,
    onError: (err, stackTrace) =>
        print('ReactionImplError $_name $err $stackTrace'),
  );

  mobx.Derivation? _derivation;

  void startTracking() {
    assert(!_scheduled);
    assert(_derivation == null);
    _previous = __globalHookContext;
    if (_previous != null) {
      _previous!._next = this;
    }
    __globalHookContext = this;
    _derivation = _reaction.startTracking();
  }

  void endTracking() {
    assert(__globalHookContext == this);
    _reaction.endTracking(_derivation);
    _derivation = null;
    __globalHookContext = _previous;
    if (hasState) {
      final effectsScheduler = HookCtxConfig.global.effectsScheduler;
      if (effectsScheduler != null) {
        _scheduled = true;
        effectsScheduler(_previous, _executeHooksLogic);
      } else {
        _executeHooksLogic();
      }
    }
  }

  void _executeHooksLogic() {
    if (HookCtxConfig.global.effectsScheduler != null && _scheduled) {
      _scheduled = false;
      final maxLength = math.max(
        _state._hookEffects.length,
        _state._previousHookEffects.length,
      );
      for (int i = 0; i < maxLength; i++) {
        _executeEffectItem(i);
      }
    }
    _state._reset();
  }

  void _executeEffectItem(int i) {
    final _previousHookEffects = _state._previousHookEffects;
    final _hookEffects = _state._hookEffects;

    final previous =
        _previousHookEffects.length > i ? _previousHookEffects[i] : null;
    final current = _hookEffects.length > i ? _hookEffects[i] : null;
    if (previous != null && current != null) {
      assert(previous.isEqual == current.isEqual);
      final prevKeys = previous.keys;
      final newKeys = current.keys;

      if (areKeysDifferent(prevKeys, newKeys, current.isEqual)) {
        previous.cleanup?.call();
        current.cleanup = current.effect();
      } else {
        current.cleanup = previous.cleanup;
      }
    } else if (current != null) {
      current.cleanup = current.effect();
    } else if (previous != null) {
      previous.cleanup?.call();
    }
  }

  void dispose() {
    assert(_derivation == null);
    if (disposed) return;
    _disposed = true;
    if (hasState) {
      _scheduled = false;
      for (final hook in _state._previousHookEffects) {
        hook.cleanup?.call();
      }
    }
    _reaction.dispose();
  }

  static bool areKeysDifferent(
    List<Object?>? prevKeys,
    List<Object?>? newKeys,
    KeysEquals isEqual,
  ) {
    int i = 0;
    return newKeys == null ||
        prevKeys == null ||
        (prevKeys.length != newKeys.length ||
            prevKeys.any((e) => !isEqual(e, newKeys[i++])));
  }
}

/// Executes [effect] and optionally disposes it using the function
/// that it returns. [effect] will be executed every time the [keys] change.
/// The previous effect will be disposed before a new one is executed.
///
/// If [keys] is null, [effect] will be executed every time, you can
/// pass an empty list if it should be executed only once.
/// The provided [keysEquals] will be used to compare the items
/// in the [keys] list.
///
/// By default, [useEffect] will be executed synchronously, however
/// one can (this is experimental) change th behavior with [HookCtxConfig].
void useEffect(
  Effect effect, [
  List<Object?>? keys,
  KeysEquals keysEquals = defaultKeysEquals,
]) {
  final _hook = HookEffect(
    effect: effect,
    keys: keys,
    isEqual: keysEquals,
  );
  final _hookEffects = globalHookContext._state._hookEffects;
  _hookEffects.add(_hook);
  if (HookCtxConfig.global.effectsScheduler == null) {
    final index = _hookEffects.length - 1;
    globalHookContext._executeEffectItem(index);
  }
}

/// Saved a mutable reference to a value.
/// If the value is mutated, it will not rebuild the component.
/// The initial value is provided by [builder] which will only be executed once.
Ref<T> useRef<T>(T Function() builder) {
  final Ref<T> ref;
  final ctx = globalHookContext._state;
  final index = ctx._hookRefIndex;
  if (index == null) {
    ref = Ref(builder());
    ctx._hookRefs.add(ref);
  } else {
    final _ref = ctx._hookRefs[index];
    ref = _ref as Ref<T>;
    ctx._hookRefIndex = index + 1;
  }
  return ref;
}

/// Saved a mutable reference to a value.
/// If the value is mutated, it will rebuild the component
/// that uses it (not necessarily the one that created it).
/// If the component in which the [Obs] is created does not access the value,
/// it will not rebuild when mutated the [Obs] is mutated.
/// The initial value is provided by [builder] which will only be executed once.
Obs<T> useObs<T>(T Function() builder) {
  final Obs<T> ref;
  final ctx = globalHookContext._state;
  final index = ctx._hookObsIndex;
  if (index == null) {
    ref = Obs(builder());
    ctx._hookObs.add(ref);
  } else {
    final _ref = ctx._hookObs[index];
    ref = _ref as Obs<T>;
    ctx._hookObsIndex = index + 1;
  }
  return ref;
}
