import 'package:flutter_nb_net/flutter_net.dart';

class UpdateInfoModel extends BaseNetModel {
  @override
  UpdateInfoModel fromJson(Map<String, dynamic> json) {
    return UpdateInfoModel.fromJson(json);
  }

  UpdateInfoModel({
    this.isUpdate,
    this.fetchOk,
    this.branch,
    this.repository,
    this.currentCommit,
    this.latestCommit,
    this.commit,
  });
  UpdateInfoModel.fromJson(dynamic json) {
    isUpdate = json['is_update'] ?? false;
    // 后端在 fetch 失败（连不上远程）时置 false，供更新页区分「检查失败」与「无更新」
    fetchOk = json['fetch_ok'] as bool?;
    branch = json['branch'];
    repository = json['repository'];
    // 远程引用缺失（如连不上 GitHub）时后端会返回空/脏 commit 数据，统一置 null，
    // 避免渲染 commit 表格时越界崩溃
    currentCommit = _parseCommit(json['current_commit']);
    latestCommit = _parseCommit(json['latest_commit']);

    commit = [];
    final rawCommit = json['commit'];
    if (rawCommit is List) {
      for (final e in rawCommit) {
        final parsed = _parseCommit(e);
        if (parsed != null) {
          commit!.add(parsed);
        }
      }
    }
  }

  /// 解析 commit 四元组 [sha1, author, isotime, message]。
  /// 长度不足 4 或含非字符串时返回 null（调用方渲染占位），保证 commit 列表只含合法条目。
  static List<String>? _parseCommit(dynamic raw) {
    if (raw is List &&
        raw.length >= 4 &&
        raw.sublist(0, 4).every((e) => e is String)) {
      return List<String>.from(raw.sublist(0, 4));
    }
    return null;
  }

  bool? isUpdate;
  bool? fetchOk;
  String? branch;
  String? repository;
  List<String>? currentCommit;
  List<String>? latestCommit;
  List<List<String>>? commit;
}