
public class StudentNotFoundException extends Exception {
    public StudentNotFoundException(int id) {
        super("No student found with ID " + id + ".");
    }
}
