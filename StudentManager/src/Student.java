
public class Student implements Comparable<Student> {
    private final int id;
    private String name;
    private int age;
    private String course;
    private double gpa;

    public Student(int id, String name, int age, String course, double gpa) {
        if (id <= 0) {
            throw new IllegalArgumentException("ID must be a positive number.");
        }
        this.id = id;
        setName(name);
        setAge(age);
        setCourse(course);
        setGpa(gpa);
    }

    public int getId() { return id; }
    public String getName() { return name; }
    public int getAge() { return age; }
    public String getCourse() { return course; }
    public double getGpa() { return gpa; }

    public void setName(String name) {
        if (name == null || name.trim().isEmpty()) {
            throw new IllegalArgumentException("Name cannot be empty.");
        }
        if (name.contains(",")) {
            throw new IllegalArgumentException("Name cannot contain commas.");
        }
        this.name = name.trim();
    }

    public void setAge(int age) {
        if (age < 3 || age > 120) {
            throw new IllegalArgumentException("Age must be between 3 and 120.");
        }
        this.age = age;
    }

    public void setCourse(String course) {
        if (course == null || course.trim().isEmpty()) {
            throw new IllegalArgumentException("Course cannot be empty.");
        }
        if (course.contains(",")) {
            throw new IllegalArgumentException("Course cannot contain commas.");
        }
        this.course = course.trim();
    }

    public void setGpa(double gpa) {
        if (gpa < 0.0 || gpa > 10.0) {
            throw new IllegalArgumentException("GPA must be between 0.0 and 10.0.");
        }
        this.gpa = gpa;
    }

    /** Serialises this student as one CSV line. */
    public String toCsv() {
        return id + "," + name + "," + age + "," + course + "," + gpa;
    }

    public static Student fromCsv(String line) {
        String[] p = line.split(",", -1);
        if (p.length != 5) {
            throw new IllegalArgumentException("Malformed record: " + line);
        }
        try {
            return new Student(
                    Integer.parseInt(p[0].trim()),
                    p[1],
                    Integer.parseInt(p[2].trim()),
                    p[3],
                    Double.parseDouble(p[4].trim()));
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Malformed record: " + line, e);
        }
    }

    @Override
    public int compareTo(Student other) {
        return Integer.compare(this.id, other.id);
    }

    @Override
    public boolean equals(Object o) {
        return o instanceof Student && ((Student) o).id == this.id;
    }

    @Override
    public int hashCode() {
        return Integer.hashCode(id);
    }

    @Override
    public String toString() {
        return String.format("%-6d %-20s %-4d %-18s %.2f", id, name, age, course, gpa);
    }
}
