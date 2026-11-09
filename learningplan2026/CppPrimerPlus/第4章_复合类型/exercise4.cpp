#include "exercises.h"
#include <iostream>
#include <string>
using namespace std;

void exercise4()
{
	string first_name, last_name;
	string name;
	cout << "Enter your first name: ";
	getline(cin, first_name);
	cout << "Enter your last name: ";
	getline(cin, last_name);
	name = last_name + ", " + first_name;
	cout << "Here's the information in a single string: " << name << endl;
}