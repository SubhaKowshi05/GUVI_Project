/** Thrown when adding a student whose ID is already in use. */
public class DuplicateStudentException extends Exception {
    public DuplicateStudentException(int id) {
        super("A student with ID " + id + " already exists.");
    }
}
