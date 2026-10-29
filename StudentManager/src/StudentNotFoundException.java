/** Thrown when an operation targets a student ID that does not exist. */
public class StudentNotFoundException extends Exception {
    public StudentNotFoundException(int id) {
        super("No student found with ID " + id + ".");
    }
}
