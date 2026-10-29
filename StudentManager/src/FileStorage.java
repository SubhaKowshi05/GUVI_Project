import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

/** Loads and saves students as a CSV file (one record per line). */
public class FileStorage {
    private final Path path;

    public FileStorage(String fileName) {
        this.path = Paths.get(fileName);
    }

    public Path getPath() {
        return path.toAbsolutePath();
    }

    /** Returns an empty list if the file does not exist yet. Bad lines are skipped with a warning. */
    public List<Student> load() throws IOException {
        List<Student> list = new ArrayList<>();
        if (!Files.exists(path)) {
            return list;
        }
        try (BufferedReader reader = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
            String line;
            int lineNo = 0;
            while ((line = reader.readLine()) != null) {
                lineNo++;
                if (line.trim().isEmpty()) {
                    continue;
                }
                try {
                    list.add(Student.fromCsv(line));
                } catch (IllegalArgumentException e) {
                    System.out.println("Warning: skipped line " + lineNo + " - " + e.getMessage());
                }
            }
        }
        return list;
    }

    /** Writes to a temp file first, then moves it over the real one so a crash cannot corrupt data. */
    public void save(List<Student> students) throws IOException {
        Path tmp = Paths.get(path.toString() + ".tmp");
        try (BufferedWriter writer = Files.newBufferedWriter(tmp, StandardCharsets.UTF_8)) {
            for (Student s : students) {
                writer.write(s.toCsv());
                writer.newLine();
            }
        }
        Files.move(tmp, path, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
    }
}
