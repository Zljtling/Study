#include "exercises.h"
#include <iostream>
#include <string>
using namespace std;

void exercise2()
{
	string name;
	string dessert;

	cout << "Enter your name: ";
	getline(cin, name);
	cout << "Enter your favorite dessert: ";
	getline(cin, dessert);
	cout << "I have some delicious " << dessert << " for you, " << name << endl;
}