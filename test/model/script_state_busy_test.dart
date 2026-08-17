import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/model/script_model.dart';

// 中文注释：锁定「前端伪状态」的两条核心契约。
// starting/stopping 只由 ScriptService 在等待后端启停响应期间置位，
// 后端 state 帧永远不会映射到它们；判断运行态必须严格 == running。
void main() {
  test('isBusy 只覆盖 starting/stopping 两个伪状态', () {
    expect(ScriptState.starting.isBusy, isTrue);
    expect(ScriptState.stopping.isBusy, isTrue);
    // 后端真实状态一律不是中间态，否则 UI 会把正常运行也当成「正在处理」而禁用按钮
    expect(ScriptState.inactive.isBusy, isFalse);
    expect(ScriptState.running.isBusy, isFalse);
    expect(ScriptState.warning.isBusy, isFalse);
    expect(ScriptState.updating.isBusy, isFalse);
  });

  test('getState 不产出伪状态：后端契约未被改动', () {
    // 覆盖已定义的 0~3 与越界/非法输入，任何输入都不得落到 starting/stopping
    final inputs = <dynamic>[0, 1, 2, 3, 4, 5, -1, 99, null, 'running', 1.5];
    for (final value in inputs) {
      final state = ScriptState.getState(value);
      expect(state.isBusy, isFalse,
          reason: 'getState($value) 产出了伪状态 $state，后端帧不应能置位中间态');
    }
    // 同时确认既有映射未被破坏
    expect(ScriptState.getState(0), ScriptState.inactive);
    expect(ScriptState.getState(1), ScriptState.running);
    expect(ScriptState.getState(2), ScriptState.warning);
    expect(ScriptState.getState(3), ScriptState.updating);
    expect(ScriptState.getState(99), ScriptState.inactive);
  });

  test('ScriptModel.isBusy 转发当前状态', () {
    final model = ScriptModel('oas1');
    model.update(state: ScriptState.inactive);
    expect(model.isBusy, isFalse);
    model.update(state: ScriptState.starting);
    expect(model.isBusy, isTrue);
    model.update(state: ScriptState.running);
    expect(model.isBusy, isFalse);
    model.update(state: ScriptState.stopping);
    expect(model.isBusy, isTrue);
  });
}
