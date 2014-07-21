package org.xtendroid.annotations

import android.app.Activity
import android.os.Bundle
import android.support.v4.app.Fragment
import android.support.v4.content.Loader
import android.view.View
import java.lang.annotation.ElementType
import java.lang.annotation.Target
import org.eclipse.xtend.lib.macro.AbstractClassProcessor
import org.eclipse.xtend.lib.macro.Active
import org.eclipse.xtend.lib.macro.TransformationContext
import org.eclipse.xtend.lib.macro.declaration.MutableClassDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableFieldDeclaration
import org.eclipse.xtend.lib.macro.declaration.Visibility

import static extension org.xtendroid.utils.NamingUtils.*
import android.support.v4.app.FragmentActivity

/**
 * 
 * TODO
 * 
 * + auto-generate Loader IDs and put them in the Activity/Fragment
 * + check if implements support LoaderCallbacks or just plain LoaderCallback in case of multiple Loader pattern
 * - add convenience functions to start, restart, stop, convenience method calls to the (support) LoaderManager
 * - add callbacks to Activity client (make it so that the Activity client, can implement multiple AsyncTaskLoaders if need be)
 * - Research: hook on to ApplicationContext instead of the activity context, or rehook the same Loader instance to the Activity context, onConfigurationChanged or onCreate even.
 */
//	val Class value = typeof(Object)
@Active(AndroidLoaderProcessor)
@Target(ElementType.TYPE)
annotation AndroidLoader {
}

class AndroidLoaderProcessor extends AbstractClassProcessor {
	
	def String getLoaderIdFromName(MutableFieldDeclaration f)
	{
		return 'LOADER_' + f.simpleName.toResourceName.toUpperCase + '_ID'
	}

	def String getLoaderIdFromName(String chars)
	{
		return 'LOADER_' + chars.toResourceName.toUpperCase + '_ID'
	}

	override doTransform(MutableClassDeclaration clazz, extension TransformationContext context) {
		
		// check if extends (support) LoaderCallbacks
		val mandatoryCallbackTypes = #['android.app.LoaderManager$LoaderCallbacks',
			'android.support.v4.app.LoaderManager$LoaderCallbacks']
		val callbackInterface = clazz.implementedInterfaces.findFirst[i|i.simpleName.endsWith('LoaderCallbacks')]
		if (callbackInterface == null) {
			clazz.addError(String.format("You must implement a LoaderCallbacks interface, either %s", mandatoryCallbackTypes.join(' or ')))
		}

		// we need at least one loader in the field
		val mandatoryLoaderTypes = #['android.content.Loader', 'android.support.v4.content.Loader']
		val loaderFields = clazz.declaredFields.filter[f| !f.type.inferred && (
			android.content.Loader.newTypeReference.isAssignableFrom(f.type) ||
			android.support.v4.content.Loader.newTypeReference.isAssignableFrom(f.type)
		)]

		if (loaderFields.size == 0) {
			clazz.addError(
				String.format("You must declare Loaders of these types in the fields: %s",
					mandatoryLoaderTypes.join(', ')))
			clazz.declaredFields.filter[f|f.type.inferred].forEach[f|f.addWarning("To make the @AndroidLoader annotation recognize your Loader fields," +
				"\nyou must declare the Loader type on the left hand side of the field expression.")]
		}
		

		// check if you are using the correct types
		// TODO rethink this check, if the user wants to shoot herself in the foot..., BgLoader is done with support
		val usingSupportCallbacks = clazz.implementedInterfaces.exists[i|'android.support.v4.app.LoaderManager$LoaderCallbacks'.endsWith(i.type.simpleName)]
		val usingSupportLoaders = loaderFields.exists[i|'android.support.v4.app.LoaderManager$LoaderCallbacks'.endsWith(i.type.simpleName)]
		if (!usingSupportCallbacks && usingSupportLoaders || usingSupportCallbacks && !usingSupportLoaders)
		{
			clazz.addWarning(
				"Don't mix support version and the standard version of Loaders and LoaderCallbacks"
			)
		}
		
		// Are loaders of the same type
		var areLoadersTheSameType = false
		for (lt : mandatoryLoaderTypes)
		{
			val loaderType = lt;
			areLoadersTheSameType = areLoadersTheSameType || loaderFields.map[f|f.type.name].fold(true, [same, name| same && loaderType.equals(name)])
		}
		if (!areLoadersTheSameType)
		{
			clazz.addWarning("Loaders should be declared with the same type. (hint: mixing support.v4 with standard Loader type?)")
		}
		  
		// generate ID tags with random numbers for each Loader
		val className = clazz.simpleName // this was added to decrease the chance of collisions (but there are no guarantees)
		val randomInitialInt = loaderFields.map[f|className + f.simpleName].join().bytes.fold(0 as int, [_1, _2| _1 as int + _2 as int])

		for (var i=0; i<loaderFields.length; i++)
		{
			val int integer = i + randomInitialInt * (i+1)
			val f = loaderFields.get(i)
			clazz.addField(f.simpleName.loaderIdFromName) [
				final = true
				static = true
				type = int.newTypeReference
				initializer = ['''«integer»''']
			]
			
		}

		// add getters for Loaders (NOTE: workaround/hack, because I don't know how to evaluate initializer exprs)
		// TODO determine how to evaluate exprs like body (method) and initializer (field)
		loaderFields.forEach[f|
			clazz.addMethod("get" + f.simpleName.toJavaIdentifier.toFirstUpper + "Loader")
			[
				visibility = Visibility.PUBLIC
				body = f.initializer
				returnType = f.type
			]
		]
		
		// neither an Activity nor Fragment
		if (clazz.extendedClass.equals(Object.newTypeReference))
		{
			clazz.addWarning("Currently the use-case beyond Activity/Fragment is out-of-scope.")
			return; // get out, you're on your own
		}
		
		// Determine that clazz is an Activity or support.v4.app.Fragment or app.Fragment
		// and try to call initLoaders, where they should be called.
		var isTypeActivity = false;
		var isTypeFragment = false;
		val fragmentWarning = "The initLoaders method must be invoked from the onViewCreated method.\n" +
			"The initLoaders method must be invoked after the views are inflated, or expect crashes when the LoaderCallback attempts to access views."
		if (clazz.extendedClass.isAssignableFrom(Activity.newTypeReference))
		{
			val onCreateMethod = clazz.declaredMethods.findFirst[m|m.simpleName.equals('onCreate')]
			if (onCreateMethod != null)
			{
				onCreateMethod.addWarning("The initLoaders method must be invoked here.\n" +
					"After the setContentView method is called, or expect crashes when the LoaderCallback attempts to access views.\n" +
					"Pro tip: use the @OnCreate annotation, to call initLoaders method.")
			}else
			{
//				val test = onCreateMethod.getBody() + ['''something '''] // this doesn't work
			}
			// TODO figure out a way to use @AndroidActivity's onCreate injection mechanism
			// NOTE: this is especially hard when I cannot (read: know not how) modify the expression of a method body
			// that is already set.
			isTypeActivity = true
		} else if (clazz.extendedClass.isAssignableFrom(Fragment.newTypeReference) ||
			clazz.extendedClass.isAssignableFrom(android.app.Fragment.newTypeReference))
		{
			val onViewCreatedMethod = clazz.declaredMethods.findFirst[m|m.simpleName.equals('onViewCreated')]
			if (onViewCreatedMethod == null)
			{
				clazz.addMethod('onViewCreated') [
					addAnnotation(Override.newAnnotationReference)
					addParameter("view", View.newTypeReference)
					addParameter("savedInstanceState", Bundle.newTypeReference)
					returnType = void.newTypeReference
					body = ['''
						initLoaders();
					''']
				]
			}else
			{
				clazz.addWarning(fragmentWarning)
			}
			isTypeFragment = true
		}
		
		val support = if (usingSupportCallbacks) "Support" else ''
		
		var String bigString = '''
			// (re)load Loader result
		'''
		
		for (f : loaderFields)
		{
			bigString += '''
			    if (getLoaderManager().getLoader(«f.loaderIdFromName») != null)
			    {
			      «IF isTypeFragment»
			      	getActivity().
			      «ENDIF»
			      get«support»LoaderManager().initLoader(«f.loaderIdFromName», null, («callbackInterface.type.simpleName») this);
			    }
			'''
			if (usingSupportCallbacks && isTypeActivity)
			{
				if (!clazz.extendedClass.isAssignableFrom(FragmentActivity.newTypeReference))
					clazz.addError("Your Activity type must extend android.support.v4.app.FragmentActivity, to use android.app.LoaderManager$LoaderCallbacks")
			}
		}
	
		// add initLoaders method
		val String _bigString = bigString.toString
		clazz.addMethod("initLoaders") [
			returnType = void.newTypeReference
			body = [_bigString]			
		]

		// if multiple Loaders then no generic param
		// if single then generic param
		
		// if onCreateLoader method does not exist then create it		
		val onCreateLoaderMethod = clazz.declaredMethods.findFirst[m|m.simpleName.equals('onCreateLoader')]
		if (onCreateLoaderMethod == null)
		{
			clazz.addMethod("onCreateLoader") [
				addParameter("LOADER_ID", int.newTypeReference)
				addParameter("args", Bundle.newTypeReference)
				addAnnotation(Override.newAnnotationReference)
				returnType = Loader.newTypeReference
				visibility = Visibility.PUBLIC
				body = [
					'''
						«loaderFields.map[f|String.format("if (%s == LOADER_ID) return get%sLoader();", f.loaderIdFromName, f.simpleName.toJavaIdentifier.toFirstUpper)].join("\n")»
						return null;
					''']
														
			]
		}else
		{
			if (onCreateLoaderMethod?.body?.toString.nullOrEmpty)
			{
				onCreateLoaderMethod.addWarning('You must return the Loader objects here, you may use the getLoaderObject synthetic method.')
			}
			clazz.addMethod('getLoaderObject') [
				addParameter("LOADER_ID", int.newTypeReference)
				addParameter("args", Bundle.newTypeReference)
				returnType = if (usingSupportCallbacks) Loader.newTypeReference else android.content.Loader.newTypeReference
				visibility = Visibility.PRIVATE
				body = [
					'''
						«loaderFields.map[f|String.format("if (%s == LOADER_ID) return get%sLoader();", f.loaderIdFromName, f.simpleName.toJavaIdentifier.toFirstUpper)].join("\n")»
						return null;
					''']				
			]
		}
	}
}
