import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class StudentRepository {
    private final Map<Integer, Student> students = new TreeMap<>();

    public void add(Student s) throws DuplicateStudentException {
        if (students.containsKey(s.getId())) {
            throw new DuplicateStudentException(s.getId());
        }
        students.put(s.getId(), s);
    }

    public Student findById(int id) throws StudentNotFoundException {
        Student s = students.get(id);
        if (s == null) {
            throw new StudentNotFoundException(id);
        }
        return s;
    }

    public void delete(int id) throws StudentNotFoundException {
        if (students.remove(id) == null) {
            throw new StudentNotFoundException(id);
        }
    }

    public List<Student> searchByName(String query) {
        String q = query.trim().toLowerCase();
        List<Student> result = new ArrayList<>();
        for (Student s : students.values()) {
            if (s.getName().toLowerCase().contains(q)) {
                result.add(s);
            }
        }
        return result;
    }

    public List<Student> getAll() {
        return new ArrayList<>(students.values());
    }

    public List<Student> getAllSorted(Comparator<Student> comparator) {
        List<Student> list = getAll();
        list.sort(comparator);
        return list;
    }

    public int size() {
        return students.size();
    }

    public void replaceAll(List<Student> loaded) {
        students.clear();
        for (Student s : loaded) {
            students.put(s.getId(), s);
        }
    }
}
