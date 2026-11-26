final _ceaEventId = RegExp(r'^[0-9]{12}\.[0-9]{4}$');

bool isCeaAgencyEventId(String id) => _ceaEventId.hasMatch(id);
