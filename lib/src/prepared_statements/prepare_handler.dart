library sqljocky.prepare_handler;

import 'dart:convert';

import 'package:logging/logging.dart';

import '../../constants.dart';
import '../buffer.dart';
import '../mysql_protocol_error.dart';
import '../handlers/handler.dart';
import '../results/field_impl.dart';

import 'prepared_query.dart';
import 'prepare_ok_packet.dart';

class PrepareHandler extends Handler {
  final String _sql;
  PrepareOkPacket _okPacket;
  int _parametersToRead;
  int _columnsToRead;
  List<FieldImpl> _parameters;
  List<FieldImpl> _columns;

  String get sql => _sql;
  PrepareOkPacket get okPacket => _okPacket;
  List<FieldImpl> get parameters => _parameters;
  List<FieldImpl> get columns => _columns;

  PrepareHandler(String this._sql) : super(new Logger("SqlJocky.PrepareHandler"));

  Buffer createRequest() {
    var encoded = utf8.encode(_sql);
    var buffer = new Buffer(encoded.length + 1);
    buffer.writeByte(COM_STMT_PREPARE);
    buffer.writeList(encoded);
    return buffer;
  }

  HandlerResponse processResponse(Buffer response) {
    log.fine("Prepare processing response");
    var packet = checkResponse(response, true);
    if (packet == null) {
      log.fine('Not an OK packet, params to read: $_parametersToRead');
      if (_parametersToRead > -1) {
        if (response[0] == PACKET_EOF) {
          log.fine("EOF");
          if (_parametersToRead != 0) {
            throw createMySqlProtocolError(
                "Unexpected EOF packet; was expecting another $_parametersToRead parameter(s)");
          }
        } else {
          var fieldPacket = new FieldImpl(response);
          log.fine("field packet: $fieldPacket");
          _parameters[_okPacket.parameterCount - _parametersToRead] =
              fieldPacket;
        }
        _parametersToRead--;
      } else if (_columnsToRead > -1) {
        if (response[0] == PACKET_EOF) {
          log.fine("EOF");
          if (_columnsToRead != 0) {
            throw createMySqlProtocolError(
                "Unexpected EOF packet; was expecting another $_columnsToRead column(s)");
          }
        } else {
          var fieldPacket = new FieldImpl(response);
          log.fine("field packet (column): $fieldPacket");
          _columns[_okPacket.columnCount - _columnsToRead] = fieldPacket;
        }
        _columnsToRead--;
      }
    } else if (packet is PrepareOkPacket) {
      log.fine(packet.toString());
      _okPacket = packet;
      _parametersToRead = packet.parameterCount;
      _columnsToRead = packet.columnCount;
      _parameters = new List<FieldImpl>(_parametersToRead);
      _columns = new List<FieldImpl>(_columnsToRead);
      if (_parametersToRead == 0) {
        _parametersToRead = -1;
      }
      if (_columnsToRead == 0) {
        _columnsToRead = -1;
      }
    }

    if (_parametersToRead == -1 && _columnsToRead == -1) {
      log.fine("finished");
      return new HandlerResponse(
          finished: true, result: new PreparedQuery(this));
    }
    return HandlerResponse.notFinished;
  }
}
