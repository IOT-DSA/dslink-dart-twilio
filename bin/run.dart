import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;
import "package:dslink/client.dart";
import "package:dslink/responder.dart";
import "package:dslink/common.dart";

const String API_VERSION = "2010-04-01";

LinkProvider link;
http.Client client = new http.Client();

main(List<String> args) async {
  link = new LinkProvider(
    args,
    "Twilio-",
    defaultNodes: {
      "Create Account": {
        r"$name": "Create Account",
        r"$is": "addAccount",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [
          {
            "name": "name",
            "type": "string"
          },
          {
            "name": "sid",
            "type": "string"
          },
          {
            "name": "token",
            "type": "string"
          }
        ]
      }
    },
    profiles: {
      "addAccount": (String path) => new AddAccountNode(path),
      "deleteAccount": (String path) => new DeleteAccountNode(path),
      "sendMessage": (String path) => new SendMessageNode(path)
    }
  );

  link.connect();
}

class AddAccountNode extends SimpleNode {
  AddAccountNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    var name = params["name"];
    var sid = params["sid"];
    var token = params["token"];

    link.addNode("/${name}", {
      r"$$twilio_token": token,
      r"$$twilio_account": sid,
      "Send Message": {
        r"$name": "Send Message",
        r"$is": "sendMessage",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [
          {
            "name": "from",
            "type": "string"
          },
          {
            "name": "to",
            "type": "string"
          },
          {
            "name": "body",
            "type": "string"
          },
          {
            "name": "media",
            "type": "string",
            "default": null
          }
        ],
        r"$columns": [
          {
            "name": "sid",
            "type": "string"
          }
        ]
      },
      "Delete Account": {
        r"$name": "Delete Account",
        r"$is": "deleteAccount",
        r"$invokable": "write",
        r"$params": [],
        r"$columns": [],
        r"$result": "values"
      }
    });

    link.save();
  }
}

class DeleteAccountNode extends SimpleNode {
  DeleteAccountNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    link.removeNode(new Path(path).parentPath);
    link.save();
    return {};
  }
}

class SendMessageNode extends SimpleNode {
  SendMessageNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var n = link["/${path.split("/")[1]}"];
    var sid = n.getConfig(r"$$twilio_account");
    var token = n.getConfig(r"$$twilio_token");
    var twilio = new Twilio(sid, token);
    return twilio.sendMessage(params["from"], params["to"], params["body"], params["media"]).then((response) {
      return {
        "sid": response["sid"]
      };
    });
  }
}

class Twilio {
  final String sid;
  final String token;

  Twilio(this.sid, this.token);

  Future<Map<String, dynamic>> sendMessage(String from, String to, String body, String mediaUrl) {
    var map = {
      "From": from,
      "To": to,
      "Body": body
    };

    if (mediaUrl != null) {
      map["MediaUrl"] = mediaUrl;
    }

    return request("POST", "/${API_VERSION}/Accounts/${sid}/Messages.json", body: map);
  }

  Future<Map<String, dynamic>> request(String method, String path, {Map<String, String> body}) {
    var r = new http.Request(method, Uri.parse("https://${sid}:${token}@api.twilio.com${path}"));

    if (body != null) {
      for (var key in body.keys.toList()) {
        if (body[key] == null) {
          body.remove(key);
        }
      }

      r.bodyFields = body;
    }
    return client.send(r).then((response) {
      return response.stream.bytesToString();
    }).then((f) {
      return JSON.decode(f);
    });
  }
}
