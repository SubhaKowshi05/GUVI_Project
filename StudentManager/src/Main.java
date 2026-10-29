import java.io.IOException;
import java.util.Comparator;
import java.util.List;
import java.util.Scanner;

/** Console UI: menu loop, input handling, and wiring of repository + storage. */
public class Main {
    private static final String DATA_FILE = "students.csv";

    private final StudentRepository repo = new StudentRepository();
    private final FileStorage storage = new FileStorage(DATA_FILE);
    private final Scanner in = new Scanner(System.in);

    public static void main(String[] args) {
        new Main().run();
    }

    private void run() {
        try {
            repo.replaceAll(storage.load());
            System.out.println("Loaded " + repo.size() + " record(s) from " + storage.getPath());
        } catch (IOException e) {
            System.out.println("Could not read data file: " + e.getMessage());
        }

        boolean running = true;
        while (running) {
            printMenu();
            switch (readLine("Choose an option: ")) {
                case "1": addStudent(); break;
                case "2": updateStudent(); break;
                case "3": deleteStudent(); break;
                case "4": viewAll(); break;
                case "5": viewOne(); break;
                case "6": searchByName(); break;
                case "7": viewSorted(); break;
                case "0": running = false; break;
                default: System.out.println("Invalid option, try again.");
            }
        }
        System.out.println("Goodbye!");
    }

    private void printMenu() {
        System.out.println("\n===== Student Record Manager =====");
        System.out.println("1. Add student");
        System.out.println("2. Update student");
        System.out.println("3. Delete student");
        System.out.println("4. View all students");
        System.out.println("5. View student by ID");
        System.out.println("6. Search by name");
        System.out.println("7. View sorted (name / GPA)");
        System.out.println("0. Exit");
    }

    // ---- actions ----

    private void addStudent() {
        try {
            int id = readInt("ID: ");
            String name = readLine("Name: ");
            int age = readInt("Age: ");
            String course = readLine("Course: ");
            double gpa = readDouble("GPA (0-10): ");
            repo.add(new Student(id, name, age, course, gpa));
            persist();
            System.out.println("Student added.");
        } catch (DuplicateStudentException | IllegalArgumentException e) {
            System.out.println("Error: " + e.getMessage());
        }
    }

    private void updateStudent() {
        try {
            Student s = repo.findById(readInt("ID of student to update: "));
            System.out.println("Leave a field blank to keep its current value.");

            String name = readLine("Name [" + s.getName() + "]: ");
            if (!name.isEmpty()) s.setName(name);

            String age = readLine("Age [" + s.getAge() + "]: ");
            if (!age.isEmpty()) s.setAge(Integer.parseInt(age));

            String course = readLine("Course [" + s.getCourse() + "]: ");
            if (!course.isEmpty()) s.setCourse(course);

            String gpa = readLine("GPA [" + s.getGpa() + "]: ");
            if (!gpa.isEmpty()) s.setGpa(Double.parseDouble(gpa));

            persist();
            System.out.println("Student updated.");
        } catch (StudentNotFoundException | IllegalArgumentException e) {
            System.out.println("Error: " + e.getMessage());
        }
    }

    private void deleteStudent() {
        try {
            int id = readInt("ID of student to delete: ");
            Student s = repo.findById(id);
            String confirm = readLine("Delete " + s.getName() + "? (y/n): ");
            if (confirm.equalsIgnoreCase("y")) {
                repo.delete(id);
                persist();
                System.out.println("Student deleted.");
            } else {
                System.out.println("Cancelled.");
            }
        } catch (StudentNotFoundException e) {
            System.out.println("Error: " + e.getMessage());
        }
    }

    private void viewAll() {
        printTable(repo.getAll());
    }

    private void viewOne() {
        try {
            printTable(List.of(repo.findById(readInt("ID: "))));
        } catch (StudentNotFoundException e) {
            System.out.println("Error: " + e.getMessage());
        }
    }

    private void searchByName() {
        printTable(repo.searchByName(readLine("Name contains: ")));
    }

    private void viewSorted() {
        String choice = readLine("Sort by (1) name  (2) GPA high-to-low: ");
        Comparator<Student> cmp = choice.equals("2")
                ? Comparator.comparingDouble(Student::getGpa).reversed()
                : Comparator.comparing(Student::getName, String.CASE_INSENSITIVE_ORDER);
        printTable(repo.getAllSorted(cmp));
    }

    // ---- helpers ----

    private void printTable(List<Student> list) {
        if (list.isEmpty()) {
            System.out.println("No records to show.");
            return;
        }
        System.out.println(String.format("%-6s %-20s %-4s %-18s %s", "ID", "Name", "Age", "Course", "GPA"));
        System.out.println("-".repeat(60));
        list.forEach(System.out::println);
        System.out.println("Total: " + list.size());
    }

    private void persist() {
        try {
            storage.save(repo.getAll());
        } catch (IOException e) {
            System.out.println("Warning: could not save data - " + e.getMessage());
        }
    }

    private String readLine(String prompt) {
        System.out.print(prompt);
        return in.hasNextLine() ? in.nextLine().trim() : "0"; // treat end of input as Exit
    }

    private int readInt(String prompt) {
        while (true) {
            try {
                return Integer.parseInt(readLine(prompt));
            } catch (NumberFormatException e) {
                System.out.println("Please enter a whole number.");
            }
        }
    }

    private double readDouble(String prompt) {
        while (true) {
            try {
                return Double.parseDouble(readLine(prompt));
            } catch (NumberFormatException e) {
                System.out.println("Please enter a number.");
            }
        }
    }
}
