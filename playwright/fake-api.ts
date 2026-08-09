import type { Page, Route } from '@playwright/test'

type FakeItem = { id: string, name: string, [key: string]: unknown }

const school = { id: 'school-1', name: 'Greenwood Academy', classrooms: ['8A', '8B', '8C', '9A', '9B', '9C', '10A', '10B', '10C'], classroomsInUse: ['8A', '8B', '9A', '10A'] }
const year = {
  id: 'year-1',
  schoolId: school.id,
  name: '2026–27',
  startDate: '2026-06-01',
  durationDays: 300,
  isCurrent: true,
  segments: [
    { id: 'term-1', name: 'Term 1', type: 'term', durationDays: 110 },
    { id: 'break-1', name: 'Autumn break', type: 'vacation', durationDays: 14 },
    { id: 'term-2', name: 'Term 2', type: 'term', durationDays: 176 }
  ]
}
const studentNames = [
  ['Aarav', 'Sharma'], ['Mira', 'Patel'], ['Vihaan', 'Reddy'], ['Anaya', 'Nair'], ['Kabir', 'Singh'],
  ['Ishita', 'Mehta'], ['Arjun', 'Kapoor'], ['Diya', 'Joshi'], ['Rohan', 'Das'], ['Sara', 'Khan'],
  ['Aditya', 'Menon'], ['Kavya', 'Rao'], ['Neil', 'Thomas'], ['Tara', 'Bose'], ['Reyansh', 'Gupta'],
  ['Myra', 'Iyer'], ['Atharv', 'Kulkarni'], ['Zoya', 'Ali'], ['Dev', 'Malhotra'], ['Saanvi', 'Jain']
]
const classDefinitions = [
  { name: 'Grade 8 Mathematics', subject: 'Mathematics', classrooms: ['8A', '8B'], description: 'Numbers, algebra and practical problem solving.' },
  { name: 'Grade 8 Science', subject: 'Science', classrooms: ['8A', '8B', '8C'], description: 'Hands-on physics, chemistry and biology.' },
  { name: 'Grade 9 English', subject: 'English', classrooms: ['9A', '9B'], description: 'Literature, writing and spoken communication.' },
  { name: 'Grade 10 History', subject: 'History', classrooms: ['10A', '10B'], description: 'World history through primary sources.' }
]
const students: FakeItem[] = studentNames.map(([firstName, lastName], index) => {
  const classIndex = Math.floor(index / 5)
  const classroom = classDefinitions[classIndex]?.classrooms[0] ?? '8A'
  const averageScore = 72 + ((index * 7) % 23)
  return {
    id: `student-${index + 1}`,
    name: `${firstName} ${lastName}`,
    firstName,
    lastName,
    email: `${firstName?.toLowerCase()}.${lastName?.toLowerCase()}@greenwood.test`,
    phone: `+91 98765 ${String(43210 + index).padStart(5, '0')}`,
    classroom,
    classrooms: [{ academicYearId: year.id, academicYearName: year.name, classroom, isCurrent: true }],
    residentAddress: `${12 + index}, Lake View Road, Bengaluru`,
    guardian: {
      name: `${['Neha', 'Rajiv', 'Meera', 'Suresh'][index % 4]} ${lastName}`,
      email: `guardian.${lastName?.toLowerCase()}${index + 1}@example.test`,
      phone: `+91 97654 ${String(41000 + index).padStart(5, '0')}`
    },
    averageScore,
    performance: {
      averageScore,
      classAverage: 82,
      completionRate: 88,
      completed: 7,
      total: 8,
      standing: `#${(index % 5) + 1} of 5`,
      trend: [64 + index % 8, 70 + index % 9, 76 + index % 10, averageScore]
    },
    behaviour: [
      { id: `behaviour-${index + 1}`, type: 'positive', note: 'Contributed thoughtfully during group work.', createdAt: '25 Jul 2026' },
      { id: `behaviour-${index + 21}`, type: index % 3 ? 'positive' : 'concern', note: index % 3 ? 'Completed classroom responsibilities early.' : 'Needs an occasional reminder to stay focused.', createdAt: '18 Jul 2026' }
    ],
    notes: [{ id: `note-${index + 1}`, note: 'Progress reviewed with the subject teacher and guardian.', createdAt: '24 Jul 2026' }]
  }
})

const classes: FakeItem[] = classDefinitions.map((definition, index) => ({
  id: `class-${index + 1}`,
  ...definition,
  studentCount: 5,
  students: students.slice(index * 5, index * 5 + 5),
  performance: {
    averageScore: 79 + index * 2,
    classAverage: 81,
    completionRate: 90 - index * 2,
    completed: 18 - index,
    total: 20,
    standing: `${index + 1}${index === 0 ? 'st' : index === 1 ? 'nd' : index === 2 ? 'rd' : 'th'} of 4`,
    trend: [68 + index, 73 + index * 2, 77 + index * 2, 82 + index]
  }
}))

const assignmentTopics = [
  ['Fractions practice', 'Algebra challenge', 'Geometry in daily life', 'Data handling project'],
  ['Cell structure lab', 'Forces worksheet', 'States of matter', 'Ecosystem journal'],
  ['Character analysis', 'Persuasive essay', 'Poetry response', 'Vocabulary portfolio'],
  ['Map skills', 'Ancient civilizations', 'Local government', 'Climate research']
]
const examTopics = ['Unit assessment', 'Practical assessment', 'Mid-term examination', 'Term review']
const assignments: FakeItem[] = classes.flatMap((classItem, classIndex) =>
  assignmentTopics[classIndex]!.map((name, assignmentIndex) => {
    const totalScore = 20 + assignmentIndex * 5
    const classStudents = students.slice(classIndex * 5, classIndex * 5 + 5)
    return {
      id: `assignment-${classIndex * 4 + assignmentIndex + 1}`,
      name,
      type: 'class',
      class: { id: classItem.id, name: classItem.name },
      dueDate: `2026-08-${String(2 + classIndex * 4 + assignmentIndex).padStart(2, '0')}`,
      totalScore,
      completion: `${4 + (assignmentIndex % 2)} / 5`,
      completionCount: 4 + (assignmentIndex % 2),
      assignees: classStudents.map((student, studentIndex) => ({
        ...student,
        score: Math.min(totalScore, Math.round(totalScore * (0.68 + ((studentIndex + assignmentIndex) % 5) * 0.06))),
        totalScore,
        completedAt: `${20 + assignmentIndex} Jul 2026`
      }))
    }
  })
)
const exams: FakeItem[] = classes.flatMap((classItem, classIndex) =>
  examTopics.map((topic, examIndex) => {
    const classStudents = students.slice(classIndex * 5, classIndex * 5 + 5)
    const averageScore = 76 + classIndex * 2 + examIndex * 3
    return {
      id: `exam-${classIndex * 4 + examIndex + 1}`,
      name: `${classItem.subject} ${topic}`,
      type: 'exam',
      class: { id: classItem.id, name: classItem.name },
      examDate: `2026-07-${String(8 + classIndex * 4 + examIndex).padStart(2, '0')}`,
      totalScore: 100,
      markedCount: examIndex === 3 ? 4 : 5,
      performance: {
        averageScore,
        classAverage: 81,
        completionRate: examIndex === 3 ? 80 : 100,
        completed: examIndex === 3 ? 4 : 5,
        total: 5,
        standing: `${classIndex + 1} of 4 classes`,
        trend: [averageScore - 9, averageScore - 5, averageScore - 2, averageScore]
      },
      students: classStudents.map((student, studentIndex) => ({
        ...student,
        score: examIndex === 3 && studentIndex === 4 ? null : 70 + ((classIndex * 7 + examIndex * 5 + studentIndex * 4) % 27),
        totalScore: 100,
        markedAt: `${14 + examIndex} Jul 2026`
      }))
    }
  })
)

for (const [classIndex, classItem] of classes.entries()) {
  classItem.assignments = assignments.slice(classIndex * 4, classIndex * 4 + 4)
  classItem.exams = exams.slice(classIndex * 4, classIndex * 4 + 4)
}
for (const [studentIndex, student] of students.entries()) {
  const classIndex = Math.floor(studentIndex / 5)
  student.assignments = assignments.slice(classIndex * 4, classIndex * 4 + 4).map(assignment => ({
    id: assignment.id,
    name: assignment.name,
    kind: 'assignment',
    classroom: classDefinitions[classIndex]?.subject,
    score: Math.round(Number(assignment.totalScore) * (0.72 + (studentIndex % 5) * 0.05)),
    totalScore: assignment.totalScore,
    markedAt: '23 Jul 2026'
  }))
  student.exams = exams.slice(classIndex * 4, classIndex * 4 + 4).map((exam, examIndex) => ({
    id: exam.id,
    name: exam.name,
    kind: 'exam',
    classroom: classDefinitions[classIndex]?.subject,
    score: examIndex === 3 && studentIndex % 5 === 4 ? null : 74 + ((studentIndex * 3 + examIndex * 5) % 22),
    totalScore: 100,
    markedAt: '20 Jul 2026'
  }))
}
const admin = { id: 'admin-1', name: 'System Admin', email: 'admin@example.test', role: 'admin', blocked: false, createdAt: '2026-06-01T09:00:00Z' }
const users = [
  admin,
  { id: 'user-1', name: 'Priya Rao', email: 'priya@example.test', role: 'user', blocked: false, createdAt: '2026-07-12T09:00:00Z' },
  { id: 'user-2', name: 'Noah Thomas', email: 'noah@example.test', role: 'user', blocked: true, createdAt: '2026-07-18T09:00:00Z' }
]

function response(path: string, setupPage: boolean, classroom?: string, emptyWorkspace = false) {
  if (path === '/admin/status') return { data: { adminExists: !setupPage } }
  if (path === '/admin/me') return { data: admin }
  if (path.startsWith('/admin/users')) return { data: users, meta: { total: users.length } }
  if (path === '/me') return { data: { id: 'teacher-1', name: 'Ananya Iyer', email: 'ananya@example.test' } }
  if (path === '/overview') return { data: { students: students.length, classes: classes.length, assignments: assignments.length, exams: exams.length } }
  if (path === '/schools') return { data: emptyWorkspace ? [] : [school], meta: { total: emptyWorkspace ? 0 : 1 } }
  if (path === '/academic-years') return { data: emptyWorkspace ? [] : [year], meta: { total: emptyWorkspace ? 0 : 1 } }
  if (path === `/academic-years/${year.id}`) return { data: year }

  const collections: Record<string, Record<string, unknown>[]> = { '/students': students, '/classes': classes, '/assignments': assignments, '/exams': exams }
  for (const [endpoint, items] of Object.entries(collections)) {
    if (path === endpoint) {
      const filtered = classroom
        ? items.filter((item) => {
            const rooms = item.classrooms
            if (Array.isArray(rooms)) {
              return rooms.some((entry) => {
                const value = typeof entry === 'string' ? entry : String((entry as { classroom?: string }).classroom ?? '')
                return value.toLowerCase() === classroom.toLowerCase()
              })
            }
            const itemClassroom = String(item.classroom ?? '')
            return itemClassroom.toLowerCase() === classroom.toLowerCase()
          })
        : items
      return { data: filtered, meta: { total: filtered.length } }
    }
    if (path.startsWith(`${endpoint}/`)) {
      const id = path.slice(endpoint.length + 1).split('/')[0]
      const item = items.find(entry => entry.id === id) ?? items[0]
      return { data: item }
    }
  }
  return { data: {} }
}

export async function mockApi(page: Page, setupPage: boolean, emptyWorkspace = false) {
  await page.route('**/api/v1/**', async (route: Route) => {
    const url = new URL(route.request().url())
    const path = url.pathname.replace('/api/v1', '')
    const classroom = url.searchParams.get('classroom') || undefined
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(response(path, setupPage, classroom, emptyWorkspace)) })
  })
}
