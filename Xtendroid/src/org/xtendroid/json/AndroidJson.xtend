package org.xtendroid.json

import java.lang.annotation.ElementType
import java.lang.annotation.Target
import java.text.DateFormat
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.List
import java.util.concurrent.ConcurrentHashMap
import org.eclipse.xtend.lib.macro.Active
import org.eclipse.xtend.lib.macro.TransformationContext
import org.eclipse.xtend.lib.macro.declaration.MutableFieldDeclaration
import org.eclipse.xtend.lib.macro.declaration.Visibility
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import android.util.JsonReader
import org.eclipse.xtend.lib.macro.declaration.MutableMemberDeclaration
import org.eclipse.xtend.lib.macro.TransformationParticipant
import org.eclipse.xtend.lib.macro.declaration.MutableClassDeclaration
import java.io.InputStream
import java.io.ByteArrayInputStream
import java.io.Reader
import java.io.StringReader
import android.util.JsonToken

import static extension org.xtendroid.utils.NamingUtils.*
import org.eclipse.xtend.lib.macro.RegisterGlobalsParticipant
import org.eclipse.xtend.lib.macro.RegisterGlobalsContext
import org.eclipse.xtend.lib.macro.declaration.ClassDeclaration

@Active(AndroidJsonProcessor)
@Target(value=#[ElementType.FIELD, ElementType.TYPE])
annotation AndroidJson {
	// Use this to explicitly state the key value (String) of the JSON Object
	// and define the expected String for DateFormat for Date fields
	// TODO Test what the value fields do with ElementType.TYPE (aliasing and Date formatting)
	String value = ""
}

/**
 * 
 * @AndroidJson annotation creates a "Json bean" that accepts a JSONObject
 * and then parses it on-demand with getters.
 * 
 */
class AndroidJsonProcessor implements TransformationParticipant<MutableMemberDeclaration>, RegisterGlobalsParticipant {

	// types supported by JSONObject
	val static supportedTypes = #{
		"java.lang.Boolean" -> 'Boolean',
		"java.lang.Double" -> 'Double',
		"java.lang.Integer" -> 'Int',
		"java.lang.Long" -> 'Long',
		"java.lang.String" -> 'String',
		"org.json.JSONObject" -> 'JSONObject',
		"org.json.JSONArray" -> 'JSONArray',
		"boolean" -> 'Boolean',
		"double" -> 'Double',
		"int" -> 'Int',
		"long" -> 'Long'
	}

	val static unsupportedTypes = #[
		"float",
		"java.lang.Float"
	]

	val public static jsonObjectFieldName = "_jsonObj"

	override doTransform(List<? extends MutableMemberDeclaration> elements, TransformationContext context) {
		elements.forEach[e| e.transform(context) ]
	}

	def static void parseJsonObject(JSONObject jsonObj, MutableClassDeclaration clazz, extension TransformationContext context)
	{
		val stringReader = new StringReader(jsonObj.toString.trim)
		val reader = new JsonReader(stringReader) // necessary to close the reader?

		reader.beginObject // consume '{'

        clazz.addConstructor [
            addParameter ('jsonObject', JSONObject.newTypeReference)
            body = '''
                this.jsonObject = jsonObject;
                this.dirtyFlag = false; // all values come from the json object
            '''
        ]

        clazz.addField ('jsonObject') [
            type = JSONObject.newTypeReference
            final = false
            visibility = Visibility.PROTECTED
        ]

        // TODO replace dirty flag all or nothing system, with per field dirty flag (do we really need that?)
		while (reader.hasNext)
		{
            val originalKey = reader.nextName
			val key = originalKey.toJavaIdentifier
			val peekValueType = reader.peek
//            val peekValue = reader.next
			switch peekValueType
			{
				case JsonToken.BOOLEAN: {
					// make a field for booleans
					clazz.addField(key) [
						type = Boolean.newTypeReference
						final = false
						visibility = Visibility.PROTECTED
					]

					clazz.addMethod("get" + key.toFirstUpper) [
						returnType = Boolean.newTypeReference
						visibility = Visibility.PUBLIC
						body = '''
						    if (!dirtyFlag)
						    {
						        this.«key» = jsonObject.getBoolean("«originalKey»");
						    }
							return this.«key»;
						'''
					]

					clazz.addMethod("set" + key.toFirstUpper) [
						addParameter('b', Boolean.newTypeReference)
						visibility = Visibility.PUBLIC
						body = '''
						    this.dirtyFlag = true; // the values were modified
							this.«key» = b;
						'''
					]
				}

                // TODO there are two types, doubles (e.g. [0-9]*.[0-9]*) and longs (e.g. [0-9]*)
				case JsonToken.NUMBER: {
					// make a field for numbers
					clazz.addField(key) [
						type = /* if(reader.nextLong..Double) Double.newTypeReference else*/ Long.newTypeReference
						final = false
						visibility = Visibility.PROTECTED
					]

					clazz.addMethod("get" + key.toFirstUpper) [
						returnType = Long.newTypeReference
						visibility = Visibility.PUBLIC
						body = '''
							return «key»;
						'''
					]

					clazz.addMethod("set" + key.toFirstUpper) [
						addParameter('l', Long.newTypeReference)
						visibility = Visibility.PUBLIC
						body = '''
						    this.dirtyFlag = true;
							this.«key» = l;
						'''
					]
				}
				case JsonToken.STRING: {
					// make a field for strings
					clazz.addField(key) [
						type = String.newTypeReference
						final = false
						visibility = Visibility.PROTECTED
					]

					clazz.addMethod("get" + key.toFirstUpper) [
						returnType = String.newTypeReference
						visibility = Visibility.PUBLIC
						body = '''
						    if (!dirtyFlag)
						    {
						        this.«key» = jsonObject.getString(«key»);
						    }
							return «key»;
						'''
					]

					clazz.addMethod("set" + key.toFirstUpper) [
						addParameter('s', String.newTypeReference)
						visibility = Visibility.PUBLIC
						body = '''
						    this.dirtyFlag = true;
							this.«key» = s;
						'''
					]
				}
/*
				// TODO register new classes at the beginning recursively
				case JsonToken.BEGIN_OBJECT:
					...

				// TODO register new classes at the beginning recursively
				// TODO put the values in a List at the initial read
				case JsonToken.BEGIN_ARRAY:
					...
*/
			}
		}
		reader.endObject
		stringReader.close
		reader.close
	}

	def dispatch void transform(MutableClassDeclaration it, extension TransformationContext context) {
		val annotationValue = (it.findAnnotation(AndroidJson.findTypeGlobally)?.getValue('value') as String).trim

		if (annotationValue.startsWith('[')) {
            it.addWarning('JSONArray detected')
			parseJsonObject(new JSONArray(annotationValue).getJSONObject(0), it, context)
        }else if (annotationValue.startsWith('{'))
        {
            it.addWarning('JSONObject detected')
            parseJsonObject(new JSONObject(annotationValue), it, context)
        } else {
			it.declaredFields.forEach[
				if (visibility == Visibility.PRIVATE && annotations.empty)
					doTransform(context)
			]
		}
	}

	def dispatch void transform(MutableFieldDeclaration it, extension TransformationContext context) {
		it.doTransform(context)
	}

	def doTransform(MutableFieldDeclaration field, extension TransformationContext context) {

		// startsWith because float[] and Float[] are also disallowed
		if (unsupportedTypes.exists[t|field.type.name.startsWith(t)])
			field.addError(field.type + " is not supported for @AndroidJson.")

		// The ctor is added if the raw JSON string container needs to be generated
		if (!field.declaringType.declaredFields.exists[it.simpleName.equals(jsonObjectFieldName)]) {

			// make a field for storing the JSONObject
			field.declaringType.addField(jsonObjectFieldName) [
				type = JSONObject.newTypeReference
				final = false
				visibility = Visibility.PROTECTED
				initializer = '''null'''
			]

			field.declaringType.addConstructor [
				addParameter("jsonObj", JSONObject.newTypeReference)
				body = [
					'''
						this.«jsonObjectFieldName» = jsonObj;
					''']
			]
		}

		// attempt to use the explicitly stated JSON member key, if stated
		val annotationValue = field.findAnnotation(AndroidJson.findTypeGlobally)?.getValue('value') as String

		// override field name with a provided name
		val jsonKey = if (!annotationValue.nullOrEmpty && !(field.type.equals(Date.newTypeReference) ||
				(field.type.equals(List.newTypeReference()) &&
					field.type.actualTypeArguments.head.equals(Date.newTypeReference()))
      ))
				annotationValue
			else
				field.simpleName

		// rename the property to _property if necessary
		// Another active annotation may want to do the same...
		if (!field.simpleName.startsWith("_")) {
			field.simpleName = "_" + field.simpleName
		}

		// make a flag for each property to indicate if it's been parsed
		// so that we can cache the result of parsing
		field.declaringType.addField(field.simpleName + "Loaded") [
			type = boolean.newTypeReference
			initializer = '''false'''
			visibility = Visibility.PROTECTED
		]

		// for Date (e.g. List<Date>, Date[], Date) members
		val dateFormat = if(annotationValue.nullOrEmpty) "yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'" else annotationValue

		// create a getter method for the property
		var getter = if(field.type.simpleName.equalsIgnoreCase("Boolean")) "is" else "get"
		field.markAsRead
		field.declaringType.addMethod(getter + field.simpleName.replaceAll('_', '').toFirstUpper) [
			primarySourceElement = field.primarySourceElement
			visibility = Visibility.PUBLIC
			returnType = field.type
			exceptions = #[JSONException.newTypeReference]
			if (supportedTypes.containsKey(field.type.name)) {

				// parse the value if it hasn't already been, then return the stored result
				body = '''
					if (!«field.simpleName»Loaded) {
					   «field.simpleName» = «jsonObjectFieldName».get«supportedTypes.get(field.type.name)»("«jsonKey»");
					   «field.simpleName»Loaded = true;
					}
					return «field.simpleName»;
				'''
			} else if (field.type.name.startsWith('java.util.Date')) {
				exceptions = #[ParseException.newTypeReference, JSONException.newTypeReference]
				if (field.type.array) {
					body = '''
						if (!«field.simpleName»Loaded) {
							final «JSONArray.newTypeReference» «field.simpleName»JsonArray = «jsonObjectFieldName».getJSONArray("«jsonKey»");
							this.«field.simpleName» = new «Date.newTypeReference»[«field.simpleName»JsonArray.length()];
							for (int i=0; i<«field.simpleName»JsonArray.length(); i++)
							{
								this.«field.simpleName»[i] = «ConcurrentDateFormatHashMap.newTypeReference.name».convertStringToDate("«dateFormat»", «field.
							simpleName»JsonArray.getString(i));
							}
							«field.simpleName»Loaded = true;
						}
						return «field.simpleName»;
					'''
				} else // single object
				{
					body = '''
						if (!«field.simpleName»Loaded) {
						   «field.simpleName» = «ConcurrentDateFormatHashMap.newTypeReference.name».convertStringToDate("«dateFormat»", «jsonObjectFieldName».getString("«jsonKey»"));
						   «field.simpleName»Loaded = true;
						}
						return «field.simpleName»;
					'''
				}
			} else if (field.type.array) {
				val baseType = field.type.arrayComponentType
				if (supportedTypes.containsKey(baseType.name)) {
					body = [
						'''
							if (!«field.simpleName»Loaded) {
								final «JSONArray.findTypeGlobally.qualifiedName» «field.simpleName»JsonArray = «jsonObjectFieldName».getJSONArray("«jsonKey»");
								this.«field.simpleName» = new «baseType»[«field.simpleName»JsonArray.length()];
								for (int i=0; i<«field.simpleName»JsonArray.length(); i++)
								{
									this.«field.simpleName»[i] = «field.simpleName»JsonArray.get«supportedTypes.get(baseType.name)»(i);
								}
								«field.simpleName»Loaded = true;
							}
							return «field.simpleName»;
							'''
					]
				} else {
					body = [
						'''
							if (!«field.simpleName»Loaded) {
								final «JSONArray.findTypeGlobally.qualifiedName» «field.simpleName»JsonArray = «jsonObjectFieldName».getJSONArray("«jsonKey»");
								this.«field.simpleName» = new «baseType»[«field.simpleName»JsonArray.length()];
								for (int i=0; i<«field.simpleName»JsonArray.length(); i++)
								{
									this.«field.simpleName»[i] = new «baseType.name»(«field.simpleName»JsonArray.getJSONObject(i));
								}
								«field.simpleName»Loaded = true;
							}
							return «field.simpleName»;
							'''
					]

				}

			} else if (field.type.name.startsWith('java.util.List')) {
				if (field.type.name.endsWith('Date>')) {
					val baseTypeName = field.type.actualTypeArguments.head.name
					body = [
						'''
							if (!«field.simpleName»Loaded) {
								final «JSONArray.findTypeGlobally.qualifiedName» «field.simpleName»JsonArray = «jsonObjectFieldName».getJSONArray("«jsonKey»");
								this.«field.simpleName» = new java.util.ArrayList<«baseTypeName»>();
								for (int i=0; i<«field.simpleName»JsonArray.length(); i++)
								{
									((java.util.ArrayList<«baseTypeName»>) this.«field.simpleName»).add(«ConcurrentDateFormatHashMap.newTypeReference.
								name».convertStringToDate("«dateFormat»", «field.simpleName»JsonArray.getString(i)));
								}
								«field.simpleName»Loaded = true;
							}
							return «field.simpleName»;
						''']
					exceptions = #[ParseException.newTypeReference, JSONException.newTypeReference]
				} else if (field.type.actualTypeArguments.exists[a|supportedTypes.containsKey(a.name)]) {
					val baseTypeName = field.type.actualTypeArguments.map[a|a.name].join()
					body = [
						'''
							if (!«field.simpleName»Loaded) {
								final «JSONArray.findTypeGlobally.qualifiedName» «field.simpleName»JsonArray = «jsonObjectFieldName».getJSONArray("«jsonKey»");
								this.«field.simpleName» = new java.util.ArrayList<«baseTypeName»>();
								for (int i=0; i<«field.simpleName»JsonArray.length(); i++)
								{
									this.«field.simpleName».add(«field.simpleName»JsonArray.get«supportedTypes.get(baseTypeName)»(i));
								}
								«field.simpleName»Loaded = true;
							}
							return «field.simpleName»;
							'''
					]
				}
			// TODO interrogate base type for the List generics param for a JSONObject param in the ctor, f.type.actualTypeArguments
				// in this current implementation, it is over-optimistically assumed that there is a ctor that takes a JSONObject for this generic type type
				else {

					//				field.type.actualTypeArguments.head.type. // no way to interrogate yet
					// custom type
					val baseTypeName = field.type.actualTypeArguments.head.name
					body = [
						'''
							if (!«field.simpleName»Loaded) {
								final «JSONArray.findTypeGlobally.qualifiedName» «field.simpleName»JsonArray = «jsonObjectFieldName».getJSONArray("«jsonKey»");
								this.«field.simpleName» = new java.util.ArrayList<«baseTypeName»>();
								for (int i=0; i<«field.simpleName»JsonArray.length(); i++)
								{
									((java.util.ArrayList<«baseTypeName»>) this.«field.simpleName»).add(new «baseTypeName»(«field.simpleName»JsonArray.getJSONObject(i)));
								}
								«field.simpleName»Loaded = true;
							}
							return «field.simpleName»;
						''']
				}

			} else if (field.declaringType.findDeclaredConstructor(JSONObject.newTypeReference()) != null) {

				// if it's single POJO that has a single ctor with a single JSONObject parameter, create it
				body = [
					'''
						if (!«field.simpleName»Loaded) {
						   «field.simpleName» = new «field.type.simpleName»(«jsonObjectFieldName».getJSONObject("«jsonKey»"));
						   «field.simpleName»Loaded = true;
						}
						return «field.simpleName»;
					''']
			} else {
				field.addError(field.type + " is not supported for @AndroidJson")
			}
		]
	}

	override doRegisterGlobals(List list, RegisterGlobalsContext registerGlobalsContext) {

		for (m : list)
		{
			try {
                // apply only on class declarations
                val c = m as ClassDeclaration
                // TODO read annotation json recursively, create the classes required
			} catch (ClassCastException ex) { /* continue */ }
		}

	}

}

class ThreadLocalDateFormatter extends ThreadLocal<DateFormat> {
	String dateFormat

	public new(String dateFormat) {
		this.dateFormat = dateFormat
	}

	public override get() {
		return super.get
	}

	protected override def DateFormat initialValue() {
		return new SimpleDateFormat(dateFormat)
	}

	public override def void set(DateFormat value) {
		super.set(value)
	}
}

/**
 * 
 * Every Thread gets a different DateFormat object, to prevent unsafe multi-threaded use
 * 
 */
class ConcurrentDateFormatHashMap {
	public val static concurrentMap = new ConcurrentHashMap<String, ThreadLocal<DateFormat>>();

	public new() {
	}

	public def static convertStringToDate(String dateFormat, String dateRaw) throws ParseException
	{
		if (!concurrentMap.containsKey(dateFormat)) {
			concurrentMap.put(dateFormat, new ThreadLocalDateFormatter(dateFormat))
		}
		return concurrentMap.get(dateFormat).get().parse(dateRaw);
	}

	public def static convertDateToString(String dateFormat, Date date) throws ParseException
	{
		if (!concurrentMap.containsKey(dateFormat)) {
			concurrentMap.put(dateFormat, new ThreadLocalDateFormatter(dateFormat))
		}
		return concurrentMap.get(dateFormat).get().format(date);
	}
}
