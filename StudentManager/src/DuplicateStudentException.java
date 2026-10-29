
public class DuplicateStudentException extends Exception {
    public DuplicateStudentException(int id) {
        super("A student with ID " + id + " already exists.");
    }
}
