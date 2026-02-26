import com.sun.net.httpserver.*;
import java.io.*;
import java.net.*;
import java.nio.file.*;

public class Server {

    static final int PORT = 3000;
    static final String DAB_URL;

    static {
        String url = System.getenv("services__data-api__http__0");
        if (url == null) url = System.getenv("services__data-api__https__0");
        if (url == null) url = System.getenv("DATA_API_HTTP");
        if (url == null) url = "http://localhost:4567";
        DAB_URL = url;
        System.out.println("DAB URL: " + DAB_URL);
    }

    public static void main(String[] args) throws Exception {
        var server = HttpServer.create(new InetSocketAddress(PORT), 0);
        server.createContext("/api/", Server::proxyApi);
        server.createContext("/", Server::serveStatic);
        server.start();
        System.out.println("Java app listening on http://localhost:" + PORT);
    }

    static void proxyApi(HttpExchange ex) throws IOException {
        String path = ex.getRequestURI().toString();
        String target = DAB_URL + path;
        try {
            var conn = (HttpURLConnection) URI.create(target).toURL().openConnection();
            conn.setRequestMethod("GET");
            byte[] body = conn.getInputStream().readAllBytes();
            ex.getResponseHeaders().set("Content-Type", "application/json");
            ex.sendResponseHeaders(conn.getResponseCode(), body.length);
            ex.getResponseBody().write(body);
        } catch (Exception e) {
            System.err.println("Proxy error: " + target + " " + e.getMessage());
            byte[] err = ("{\"error\":\"" + e.getMessage().replace("\"", "'") + "\"}").getBytes();
            ex.getResponseHeaders().set("Content-Type", "application/json");
            ex.sendResponseHeaders(502, err.length);
            ex.getResponseBody().write(err);
        } finally {
            ex.close();
        }
    }

    static void serveStatic(HttpExchange ex) throws IOException {
        String path = ex.getRequestURI().getPath();
        if (path.equals("/")) path = "/index.html";
        Path file = Path.of("static" + path);
        if (Files.exists(file)) {
            byte[] data = Files.readAllBytes(file);
            String ct = switch (path.substring(path.lastIndexOf('.'))) {
                case ".html" -> "text/html";
                case ".js", ".jsx" -> "application/javascript";
                case ".css" -> "text/css";
                case ".json" -> "application/json";
                default -> "application/octet-stream";
            };
            ex.getResponseHeaders().set("Content-Type", ct);
            ex.sendResponseHeaders(200, data.length);
            ex.getResponseBody().write(data);
        } else {
            ex.sendResponseHeaders(404, -1);
        }
        ex.close();
    }
}
