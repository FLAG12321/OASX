import 'package:flutter_nb_net/flutter_net.dart';

/// 后端 /home/update_progress 返回的更新进度快照。
class UpdateProgressModel extends BaseNetModel {
  @override
  UpdateProgressModel fromJson(Map<String, dynamic> json) {
    return UpdateProgressModel.fromJson(json);
  }

  UpdateProgressModel({
    this.status,
    this.step,
    this.branch,
    this.logs,
    this.finished,
  });

  UpdateProgressModel.fromJson(dynamic json) {
    status = json['status'];
    step = json['step'];
    branch = json['branch'];
    logs = (json['logs'] as List<dynamic>?)?.cast<String>() ?? [];
    finished = json['finished'];
  }

  String? status;
  String? step;
  String? branch;
  List<String>? logs;
  bool? finished;
}
