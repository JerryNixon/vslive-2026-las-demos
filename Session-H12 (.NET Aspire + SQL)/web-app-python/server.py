from flask import Flask, jsonify, request
import os, requests

app = Flask(__name__, static_folder="static", static_url_path="")

dab_url = (
    os.environ.get("services__data-api__https__0")
    or os.environ.get("services__data-api__http__0")
    or "http://localhost:4567"
)


@app.route("/")
def index():
    return app.send_static_file("index.html")


@app.route("/api/<entity>")
def proxy(entity):
    url = f"{dab_url}/api/{entity}"
    try:
        resp = requests.get(url, params=request.args)
        return jsonify(resp.json()), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 502


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 3000))
    app.run(host="0.0.0.0", port=port)
