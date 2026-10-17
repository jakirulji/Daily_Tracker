import 'package:flutter/material.dart';
import 'exam_widget.dart';
import 'store.dart';
import 'ui.dart';

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});
  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  @override
  void initState() {
    super.initState();
    final i = st.profiles.indexWhere((p) => p['t'] != 'prayer');
    if (i >= 0 && st.cur != i) st.switchTo(i);
  }

  List<Map> get exams => st.exams..sort((a, b) => (a['date'] as String? ?? '').compareTo(b['date'] as String? ?? ''));

  int days(String value) {
    final d = DateTime.tryParse(value);
    if (d == null) return 0;
    final n = DateTime.now();
    return DateTime(d.year,d.month,d.day).difference(DateTime(n.year,n.month,n.day)).inDays;
  }

  String dateLabel(String value) {
    final d = DateTime.tryParse(value);
    return d == null ? value : d.day.toString().padLeft(2,'0') + '/' + d.month.toString().padLeft(2,'0') + '/' + d.year.toString();
  }

  void save() { st.save(); ExamWidgetSync.update(); }

  Future<void> addExam({Map? old}) async {
    final title = TextEditingController(text: old?['title'] ?? '');
    final type = TextEditingController(text: old?['type'] ?? '');
    final now = DateTime.now();
    DateTime groupStart = DateTime.tryParse(old?['startDate']?.toString() ?? old?['date']?.toString() ?? '') ?? now;
    DateTime groupEnd = DateTime.tryParse(old?['endDate']?.toString() ?? old?['date']?.toString() ?? '') ?? now.add(const Duration(days:30));
    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    Future<DateTime?> chooseDate(BuildContext d, DateTime value) {
      final n=DateTime.now();
      return showDatePicker(context:d, initialDate:value.isBefore(DateTime(n.year,n.month,n.day))?DateTime(n.year,n.month,n.day):value, firstDate:DateTime(n.year,n.month,n.day),lastDate:DateTime(2100));
    }
    final result = await showDialog<Map>(context: context, builder: (d) => StatefulBuilder(builder: (d,set) => AlertDialog(
      title: Text(old == null ? 'Add exam group' : 'Edit exam group'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller:title, autofocus:true, decoration:const InputDecoration(labelText:'Exam group name',hintText:'e.g. BHMS Supply Examination')),
        TextField(controller:type, decoration:const InputDecoration(labelText:'Session / year (optional)')),
        ListTile(contentPadding:EdgeInsets.zero, leading:const Icon(Icons.event_available_outlined), title:const Text('Group start date'), subtitle:Text(dateLabel(iso(groupStart))), onTap:() async { final p=await chooseDate(d,groupStart); if(p!=null) set(()=>groupStart=p); }),
        ListTile(contentPadding:EdgeInsets.zero, leading:const Icon(Icons.event_note_outlined), title:const Text('Group end date'), subtitle:Text(dateLabel(iso(groupEnd))), onTap:() async { final p=await chooseDate(d,groupEnd); if(p!=null) set(()=>groupEnd=p); }),
        const Padding(padding:EdgeInsets.only(top:4),child:Text('You can set a separate exam date for every subject too.',style:TextStyle(fontSize:12))),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Cancel')),FilledButton(onPressed:(){
        if(title.text.trim().isNotEmpty) Navigator.pop(d, {'title':title.text.trim(),'type':type.text.trim(),'startDate':iso(groupStart),'endDate':iso(groupEnd),'date':iso(groupEnd)});
      },child:const Text('Save'))],
    )));
    if(result==null || !mounted) return;
    if(old==null) exams.add({...result,'subjects':<Map>[],'done':false}); else old.addAll(result);
    save(); setState((){});
  }

  Future<void> addSubject(Map exam,{Map? old}) async {
    final name=TextEditingController(text:old?['name']??'');
    final input=TextEditingController(text:List<Map>.from(old?['topics']??[]).map((t)=>t['name']).join('\n'));
    DateTime subjectDate = DateTime.tryParse(old?['date']?.toString() ?? exam['endDate']?.toString() ?? exam['date']?.toString() ?? '') ?? DateTime.now().add(const Duration(days:30));
    String isoSubject(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    final result=await showDialog<Map>(context:context,builder:(d)=>StatefulBuilder(builder:(d,set)=>AlertDialog(
      title:Text(old==null?'Add subject & syllabus':'Edit subject'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,autofocus:true,decoration:const InputDecoration(labelText:'Subject name')),
        ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.calendar_month),title:const Text('Subject exam date'),subtitle:Text(dateLabel(isoSubject(subjectDate))),onTap:() async { final n=DateTime.now(); final p=await showDatePicker(context:d,initialDate:subjectDate.isBefore(DateTime(n.year,n.month,n.day))?DateTime(n.year,n.month,n.day):subjectDate,firstDate:DateTime(n.year,n.month,n.day),lastDate:DateTime(2100)); if(p!=null)set(()=>subjectDate=p); }),
        const SizedBox(height:10),
        TextField(controller:input,minLines:4,maxLines:8,decoration:const InputDecoration(labelText:'Syllabus topics',hintText:'One topic per line')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Cancel')),FilledButton(onPressed:(){
        if(name.text.trim().isNotEmpty){
          final previous=List<Map>.from(old?['topics']??[]);
          final names=input.text.split('\n').map((x)=>x.trim()).where((x)=>x.isNotEmpty);
          final ts=names.map((n){final found=previous.where((t)=>t['name']==n).toList(); return found.isEmpty? <String,dynamic>{'name':n,'done':false}:Map<String,dynamic>.from(found.first);}).toList();
          Navigator.pop(d,{'name':name.text.trim(),'date':isoSubject(subjectDate),'topics':ts});
        }
      },child:const Text('Save'))],
    )));
    if(result==null || !mounted)return;
    final list=List<Map>.from(exam['subjects']??[]);
    if(old==null) list.add(result); else {final i=list.indexOf(old);if(i>=0)list[i]=result;}
    exam['subjects']=list; save();setState((){});
  }

  Future<void> deleteExam(Map e) async {
    if(!await confirm(context,'Delete "'+(e['title']??'exam').toString()+'" and its syllabus?'))return;
    exams.remove(e);save();if(mounted)setState((){});
  }

  @override
  Widget build(BuildContext context) {
    final cs=Theme.of(context).colorScheme;
    final all=exams;
    bool hasUpcomingDate(Map e) {
      final subjects=List<Map>.from(e['subjects']??[]);
      final groupDate=(e['endDate']??e['date']??'').toString();
      final dates=subjects.map((s)=>DateTime.tryParse((s['date']??groupDate).toString())).whereType<DateTime>().toList();
      if(dates.any((d)=>days(d.toIso8601String())>=0)) return true;
      return days(groupDate)>=0;
    }
    final upcoming=all.where((e)=>e['done']!=true && hasUpcomingDate(e)).toList();
    final past=all.where((e)=>e['done']==true || !hasUpcomingDate(e)).toList();
    return Scaffold(
      appBar:AppBar(title:const Text('Exam Tracker')),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>addExam(),icon:const Icon(Icons.add),label:const Text('Add exam')),
      body:all.isEmpty ? Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Icon(Icons.event_note_rounded,size:62,color:cs.primary),const SizedBox(height:14),
        Text('Plan your next exam',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
        const SizedBox(height:8),const Text('Add exam dates, subjects, syllabus topics and track preparation from your dashboard.',textAlign:TextAlign.center),
        const SizedBox(height:16),FilledButton.icon(onPressed:()=>addExam(),icon:const Icon(Icons.add),label:const Text('Add your first exam')),
      ]))) : ListView(padding:const EdgeInsets.fromLTRB(16,12,16,90),children:[
        _heading('UPCOMING EXAMS',upcoming.length,cs.primary),
        if(upcoming.isEmpty) const Padding(padding:EdgeInsets.all(12),child:Text('No upcoming exams.')),
        for(final e in upcoming) _examCard(e,cs),
        if(past.isNotEmpty)...[_heading('PAST / COMPLETED',past.length,cs.outline),for(final e in past)_examCard(e,cs)],
      ]),
    );
  }

  Widget _heading(String label,int count,Color color)=>Padding(padding:const EdgeInsets.only(top:8,bottom:10),child:Row(children:[Expanded(child:Text(label,style:TextStyle(fontSize:11,letterSpacing:1.2,fontWeight:FontWeight.w900,color:color))),Text(count.toString(),style:TextStyle(color:color,fontWeight:FontWeight.w900))]));

  Widget _examCard(Map e,ColorScheme cs){
    final subjects=List<Map>.from(e['subjects']??[]);
    final total=subjects.fold<int>(0,(sum,s)=>sum+List<Map>.from(s['topics']??[]).length);
    final complete=subjects.fold<int>(0,(sum,s)=>sum+List<Map>.from(s['topics']??[]).where((t)=>t['done']==true).length);
    final groupDate=(e['endDate']??e['date']??'').toString();
    final today=DateTime.now();
    final todayOnly=DateTime(today.year,today.month,today.day);
    final subjectDates=subjects.map((s)=>DateTime.tryParse((s['date']??groupDate).toString())).whereType<DateTime>().toList()..sort();
    final upcomingDates=subjectDates.where((x)=>!DateTime(x.year,x.month,x.day).isBefore(todayOnly)).toList();
    final effectiveDate=upcomingDates.isNotEmpty?upcomingDates.first:(DateTime.tryParse(groupDate)??(subjectDates.isEmpty?null:subjectDates.first));
    final d=effectiveDate==null?0:DateTime(effectiveDate.year,effectiveDate.month,effectiveDate.day).difference(todayOnly).inDays;
    final past=d<0||e['done']==true;
    final status=e['done']==true?'Completed':d<0?'Past exam':d==0?'Today':d==1?'Tomorrow':d.toString()+' days left';
    return Card(elevation:0,margin:const EdgeInsets.only(bottom:12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22),side:BorderSide(color:cs.outlineVariant)),child:ExpansionTile(
      key:ValueKey((e['title']??'').toString()+(e['date']??'').toString()),
      leading:CircleAvatar(backgroundColor:past?cs.surfaceContainerHighest:cs.tertiaryContainer,child:Icon(past?Icons.history_rounded:Icons.school_rounded)),
      title:Text((e['title']??'Exam').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
      subtitle:Text((e['startDate']!=null?dateLabel(e['startDate'].toString())+' – ':'')+dateLabel((e['endDate']??e['date']??'').toString())+' • '+status+(((e['type']??'').toString().isEmpty)?'':'\n'+e['type'].toString())),
      childrenPadding:const EdgeInsets.fromLTRB(14,0,14,14),
      children:[
        Row(children:[const Expanded(child:Text('Syllabus preparation',style:TextStyle(fontWeight:FontWeight.w800))),Text(complete.toString()+'/'+total.toString()+' topics')]),
        const SizedBox(height:8),ClipRRect(borderRadius:BorderRadius.circular(99),child:LinearProgressIndicator(value:total==0?0:complete/total,minHeight:7)),
        if(subjects.isEmpty) const Padding(padding:EdgeInsets.all(10),child:Text('Add a subject and enter its syllabus topics.')),
        for(final s in subjects)_subject(e,s,cs),
        Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:()=>addSubject(e),icon:const Icon(Icons.add),label:const Text('Add subject'))),
        const Divider(),
        Wrap(spacing:8,children:[
          OutlinedButton.icon(onPressed:()=>addExam(old:e),icon:const Icon(Icons.edit_outlined),label:const Text('Edit')),
          OutlinedButton.icon(onPressed:(){e['done']=e['done']!=true;save();setState((){});},icon:const Icon(Icons.check_circle_outline),label:Text(e['done']==true?'Reopen':'Mark completed')),
          IconButton(onPressed:()=>deleteExam(e),icon:const Icon(Icons.delete_outline)),
        ]),
      ],
    ));
  }

  Widget _subject(Map exam,Map subject,ColorScheme cs){
    final topics=List<Map>.from(subject['topics']??[]);
    final done=topics.where((t)=>t['done']==true).length;
    return Container(margin:const EdgeInsets.only(top:9),padding:const EdgeInsets.fromLTRB(10,8,6,8),decoration:BoxDecoration(color:cs.surfaceContainerLow,borderRadius:BorderRadius.circular(15)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((subject['name']??'Subject').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),Text('Exam: '+dateLabel((subject['date']??exam['endDate']??exam['date']??'').toString()),style:TextStyle(fontSize:11,color:cs.onSurfaceVariant))])),Text('${done}/${topics.length} · ${topics.isEmpty?0:(done*100/topics.length).round()}%',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),IconButton(visualDensity:VisualDensity.compact,onPressed:()=>addSubject(exam,old:subject),icon:const Icon(Icons.edit_outlined,size:18))]),
      const SizedBox(height:5),
      ClipRRect(borderRadius:BorderRadius.circular(99),child:LinearProgressIndicator(value:topics.isEmpty?0:done/topics.length,minHeight:4,backgroundColor:cs.outlineVariant.withOpacity(.45))),
      if(topics.isEmpty) const Padding(padding:EdgeInsets.only(left:10,bottom:6),child:Text('No topics added yet.')),
      for(final t in topics) CheckboxListTile(dense:true,contentPadding:const EdgeInsets.only(left:2),visualDensity:VisualDensity.compact,value:t['done']==true,title:Text((t['name']??'').toString(),style:TextStyle(fontSize:13,decoration:t['done']==true?TextDecoration.lineThrough:null)),onChanged:(v){t['done']=v==true;save();setState((){});}),
    ]));
  }
}
